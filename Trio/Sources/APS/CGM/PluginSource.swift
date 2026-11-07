import AccuChekKit
import CGMBLEKit
import Combine
import EversenseKit
import Foundation
import G7SensorKit
import LibreLoop
import LibreTransmitter
import LoopKit
import LoopKitUI
import SyaiKit

final class PluginSource: GlucoseSource {
    private let processQueue = DispatchQueue(label: "CGMPluginSource.processQueue")
    private let glucoseStorage: GlucoseStorage!
    private let deviceLogStore: DeviceLogStore
    var glucoseManager: FetchGlucoseManager?

    let cgmDisplayState = CurrentValueSubject<CgmDisplayState?, Never>(nil)
    let cgmProgressHighlight = CurrentValueSubject<DeviceLifecycleProgress?, Never>(nil)

    var cgmManager: CGMManagerUI? {
        didSet { publishCGMStatus() }
    }

    var cgmHasValidSensorSession: Bool = false

    init(glucoseStorage: GlucoseStorage, glucoseManager: FetchGlucoseManager, deviceLogStore: DeviceLogStore) {
        self.glucoseStorage = glucoseStorage
        self.deviceLogStore = deviceLogStore
        self.glucoseManager = glucoseManager

        cgmManager = glucoseManager.cgmManager
        cgmManager?.delegateQueue = processQueue
        cgmManager?.cgmManagerDelegate = self
        // didSet doesn't fire from the defining class's own init.
        publishCGMStatus()
    }

    /// Republishes the manager's lifecycle/highlight to the subjects.
    /// Called from `cgmManager.didSet` and after delegate state updates.
    func publishCGMStatus() {
        if let highlight = cgmManager?.cgmStatusHighlight {
            cgmDisplayState.value = CgmDisplayState(
                localizedMessage: highlight.localizedMessage,
                imageName: highlight.imageName,
                status: CgmDisplayStatus.from(highlight.state)
            )
        } else {
            cgmDisplayState.value = nil
        }
        cgmProgressHighlight.value = cgmManager?.cgmLifecycleProgress
    }

    /// The glucose timer's nudge: asks the CGM manager for new data when some is due. The readings reach Trio through
    /// the delegate (`cgmManager(_:hasNew:)`), never through this publisher, which finishes empty.
    ///
    /// Before, a `Future` answered with an empty list that a filter then dropped, and a 5-minute timeout ended it with
    /// another empty list: nothing ever came through it. The filter's check of that list crashed the app once
    /// (6 November, build 134: EXC_BAD_ACCESS in `PluginSource.fetch`, `!$0.isEmpty`, on the glucose manager's queue,
    /// with the answer delivered from the CGM manager's).
    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        fetchIfNeeded()
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        processQueue.async { [weak self] in
            // what it returns is left out on purpose: it comes from the Share client and would race the CGM's own
            // reading (G6 with Share credentials only)
            self?.cgmManager?.fetchNewDataIfNeeded { _ in }
        }
        return Empty().eraseToAnyPublisher()
    }

    deinit {
        // dexcomManager.transmitter.stopScanning()
    }
}

extension PluginSource: CGMManagerDelegate {
    func deviceManager(
        _ manager: LoopKit.DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type: LoopKit.DeviceLogEntryType,
        message: String,
        completion: ((Error?) -> Void)?
    ) {
        deviceLogStore.log(
            managerIdentifier: manager.pluginIdentifier,
            deviceIdentifier: deviceIdentifier,
            type: type,
            message: message,
            completion: completion
        )
    }

    /// Forwards CGMManager-issued alerts into the unified `TrioAlertManager`
    /// pipeline so they get the same in-app banner + UN scheduling + history
    /// logging treatment as everything else. Used to be a no-op; on
    /// dev-libre3 / LibreLoop builds that meant CGM-issued alerts (sensor
    /// failure, signal loss, expiry, etc.) silently dropped.
    nonisolated func issueAlert(_ alert: LoopKit.Alert) {
        processQueue.async { self.glucoseManager?.trioAlertManager?.issueAlert(alert) }
    }

    nonisolated func retractAlert(identifier: LoopKit.Alert.Identifier) {
        processQueue.async { self.glucoseManager?.trioAlertManager?.retractAlert(identifier: identifier) }
    }

    /// LoopKit asks this on reconnect to avoid re-issuing an alert that's
    /// still live. `TrioAlertManager` deduplicates downstream via its own
    /// throttler and live-alert table, so answering "no" here is safe — at
    /// worst we get one duplicate banner, which the throttler suppresses.
    func doesIssuedAlertExist(identifier _: LoopKit.Alert.Identifier) async throws -> Bool {
        false
    }

    func lookupAllUnretracted(managerIdentifier _: String) async throws -> [LoopKit.PersistedAlert] {
        []
    }

    func lookupAllUnacknowledgedUnretracted(managerIdentifier _: String) async throws -> [LoopKit.PersistedAlert] {
        []
    }

    /// LoopKit calls this when a manager itself decides an alert is no
    /// longer relevant. Mirror the action on our pipeline so the in-app
    /// banner, scheduled UN, and history all clear.
    nonisolated func recordRetractedAlert(_ alert: LoopKit.Alert, at _: Date) async throws {
        processQueue.async { self.glucoseManager?.trioAlertManager?.retractAlert(identifier: alert.identifier) }
    }

    func cgmManagerWantsDeletion(_ manager: CGMManager) async {
        info(.cgm, "CGM \(manager.pluginIdentifier) requested removal")
        await glucoseManager?.deleteGlucoseSource()
    }

    func cgmManager(_: CGMManager, hasNew readingResult: CGMReadingResult) {
        processQueue.async { [weak self] in
            guard let self = self else { return }

            dispatchPrecondition(condition: .onQueue(self.processQueue))

            switch self.readCGMResult(readingResult: readingResult) {
            case let .success(glucose):
                self.glucoseManager?.newGlucoseFromCgmManager(newGlucose: glucose)
            case let .failure(error):
                debug(.cgm, "CGM reading not usable: \(error.localizedDescription)")
            }

            self.glucoseManager?.reportCGMSensorObservation(self.currentSensorObservation())

            self.publishCGMStatus()
        }
    }

    func cgmManager(_: LoopKit.CGMManager, hasNew events: [LoopKit.PersistedCgmEvent]) {
        processQueue.async { [weak self] in
            guard let self = self else { return }

            dispatchPrecondition(condition: .onQueue(self.processQueue))

            // TODO: Events in APS ?
            // currently only display in log the date of the event
            events.forEach { event in
                debug(.cgm, "CGM event \(event.type) at \(event.date)")

                if event.type == .sensorStart {
                    info(.cgm, "Sensor started")
                    self.glucoseManager?.removeCalibrations()
                    self.glucoseManager?.startCGMSensorSession(startedAt: event.date)
                }
            }
        }
    }

    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(processQueue))

        return glucoseStorage.lastGlucoseDate()
    }

    func cgmManagerDidUpdateState(_ cgmManager: CGMManager) {
        processQueue.async { [weak self] in
            guard let self = self else { return }

            dispatchPrecondition(condition: .onQueue(self.processQueue))

            guard let fetchGlucoseManager = self.glucoseManager else {
                debug(.cgm, "CGM state update ignored: no glucose manager")
                return
            }
            // Adjust app-specific NS Upload setting value when CGM setting is changed
            fetchGlucoseManager.settingsManager.settings.uploadGlucose = cgmManager.shouldSyncToRemoteService

            fetchGlucoseManager.updateGlucoseSource(
                cgmGlucoseSourceType: fetchGlucoseManager.settingsManager.settings.cgm,
                cgmGlucosePluginId: fetchGlucoseManager.settingsManager.settings.cgmPluginIdentifier,
                newManager: cgmManager as? CGMManagerUI
            )

            self.publishCGMStatus()
        }
    }

    func credentialStoragePrefix(for _: CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        UUID().uuidString
    }

    func cgmManager(_: CGMManager, didUpdate status: CGMManagerStatus) {
        debug(.cgm, "CGM status: valid sensor session \(status.hasValidSensorSession)")
        processQueue.async { [weak self] in
            guard let self = self else { return }

            dispatchPrecondition(condition: .onQueue(self.processQueue))

            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                info(.cgm, status.hasValidSensorSession ? "Sensor session started" : "Sensor session ended")
                self.cgmHasValidSensorSession = status.hasValidSensorSession
            }
        }
    }

    // The live reading carries the sensor state; a backfill's .newData says nothing about it.
    private func currentSensorObservation() -> CGMSensorObservation {
        if let cgmTransmitterManager = cgmManager as? G7CGMManager {
            return cgmTransmitterManager.latestReading?.algorithmState.observation ?? .unavailable
        } else if let cgmTransmitterManager = cgmManager as? G6CGMManager {
            return cgmTransmitterManager.latestReading?.state.observation ?? .unavailable
        }
        return .unavailable
    }

    private func readCGMResult(readingResult: CGMReadingResult) -> Result<[BloodGlucose], Error> {
        if glucoseManager?.glucoseSource == nil {
            debug(.cgm, "CGM reading received with no glucose source set")
        }

        switch readingResult {
        case let .newData(values):

            var sensorActivatedAt: Date?
            var sensorStartDate: Date?
            var sensorTransmitterID: String?

            /// SAGE
            if let cgmTransmitterManager = cgmManager as? LibreTransmitterManagerV3 {
                let sensorInfo = cgmTransmitterManager.sensorInfoObservable
                sensorActivatedAt = sensorInfo.activatedAt
                sensorStartDate = sensorInfo.activatedAt
                sensorTransmitterID = sensorInfo.sensorSerial
            } else if let cgmTransmitterManager = cgmManager as? G5CGMManager {
                let latestReading = cgmTransmitterManager.latestReading
                sensorActivatedAt = latestReading?.activationDate
                sensorStartDate = latestReading?.sessionStartDate
                sensorTransmitterID = latestReading?.transmitterID
            } else if let cgmTransmitterManager = cgmManager as? G6CGMManager {
                let latestReading = cgmTransmitterManager.latestReading
                sensorActivatedAt = latestReading?.activationDate
                sensorStartDate = latestReading?.sessionStartDate
                sensorTransmitterID = latestReading?.transmitterID
            } else if let cgmTransmitterManager = cgmManager as? G7CGMManager {
                sensorActivatedAt = cgmTransmitterManager.sensorActivatedAt
                sensorStartDate = cgmTransmitterManager.sensorActivatedAt
                sensorTransmitterID = cgmTransmitterManager.sensorName
            } else if let cgmTransmitterManager = cgmManager as? LibreLoopCGMManager {
                sensorActivatedAt = cgmTransmitterManager.state.activatedAt
                sensorStartDate = cgmTransmitterManager.state.activatedAt
                sensorTransmitterID = cgmTransmitterManager.state.sensorSerial
            } else if let cgmTransmitterManager = cgmManager as? AccuChekCgmManager {
                sensorActivatedAt = cgmTransmitterManager.state.cgmStartTime
                sensorStartDate = cgmTransmitterManager.state.cgmStartTime
                sensorTransmitterID = cgmTransmitterManager.state.sensorInfo?.serialNumber
            } else if let cgmTransmitterManager = cgmManager as? EversenseCGMManager {
                sensorActivatedAt = cgmTransmitterManager.state.activatedAt
                sensorStartDate = cgmTransmitterManager.state.activatedAt
                sensorTransmitterID = cgmTransmitterManager.state.bleNameString
            } else if let cgmTransmitterManager = cgmManager as? SyaiCGMManager {
                sensorActivatedAt = cgmTransmitterManager.state.activatedAt
                sensorStartDate = cgmTransmitterManager.state.activatedAt
                sensorTransmitterID = cgmTransmitterManager.state.mac
            }

            // isDisplayOnly means "shifted for visual consistency after calibration"
            // (LoopKit), not "unsafe to dose"; drivers withhold sensor-reported faults.
            let bloodGlucose = values.compactMap { newGlucoseSample -> BloodGlucose? in
                if newGlucoseSample.isDisplayOnly {
                    debug(.cgm, "Display-only reading at \(newGlucoseSample.date), storing it")
                }

                let quantity = newGlucoseSample.quantity

                let value = Int(quantity.doubleValue(for: .milligramsPerDeciliter))

                if newGlucoseSample.wasUserEntered {
                    // Store the calibration for the sensor as manual glucose
                    return BloodGlucose(
                        id: UUID().uuidString,
                        mbg: value,
                        date: Decimal(Int(newGlucoseSample.date.timeIntervalSince1970 * 1000)),
                        dateString: newGlucoseSample.date,
                        filtered: nil,
                        noise: nil,
                        glucose: value,
                        type: "mbg",
                        activationDate: sensorActivatedAt,
                        sessionStartDate: sensorStartDate,
                        transmitterID: sensorTransmitterID
                    )
                }

                return BloodGlucose(
                    id: UUID().uuidString,
                    sgv: value,
                    direction: .init(trendType: newGlucoseSample.trend),
                    date: Decimal(Int(newGlucoseSample.date.timeIntervalSince1970 * 1000)),
                    dateString: newGlucoseSample.date,
                    unfiltered: Decimal(value),
                    filtered: nil,
                    noise: nil,
                    glucose: value,
                    type: "sgv",
                    activationDate: sensorActivatedAt,
                    sessionStartDate: sensorStartDate,
                    transmitterID: sensorTransmitterID
                )
            }
            return .success(bloodGlucose)
        case .unreliableData:
            // loopManager.receivedUnreliableCGMReading()
            return .failure(GlucoseDataError.unreliableData)
        case .noData:
            return .failure(GlucoseDataError.noData)
        case let .error(error):
            return .failure(error)
        }
    }
}

extension PluginSource {
    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Plugin CGM source"]
    }
}
