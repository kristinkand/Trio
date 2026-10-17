import Foundation
import Observation
import UserNotifications
import WatchKit

/// Reads the G7 directly from the watch, in the watch's own display slot, so
/// glucose keeps arriving (and lows and highs still alert) when the iPhone is
/// out of reach. Display and alerts only: nothing here doses.
///
/// The phone supplies what the watch cannot find out itself: which sensor,
/// its pairing code, the alarm thresholds and the display units. They arrive
/// with every watch state update and are kept, so the watch can carry on
/// alone afterwards.
@Observable final class WatchG7Reader: WatchG7SessionDelegate {
    static let shared = WatchG7Reader()

    // MARK: - Settings and phone-supplied values (persisted)

    /// The user's switch on the watch. Off by default: nothing touches
    /// Bluetooth until it is turned on.
    private(set) var isEnabled: Bool
    private(set) var sensorName: String?
    private(set) var pairingCode: String?
    /// False once the phone has said it is not reading a G7 directly.
    private(set) var phoneUsesG7Direct: Bool?
    private(set) var units: String
    private(set) var urgentLowMgDL: Double
    private(set) var lowMgDL: Double?
    private(set) var highMgDL: Double?

    /// The watch's own key for the sensor, from its own pairing.
    private(set) var hasWatchKey: Bool

    // MARK: - Live state

    /// The watch's own readings, oldest first, kept for 12 hours.
    private(set) var history: [WatchG7Reading]
    private(set) var isConnected = false
    private(set) var isSearching = false
    private(set) var needsCodeForSensor: String? = nil
    /// The sensor's state when it last answered without a usable reading (warm-up, failed, ...).
    private(set) var sensorProblem: String? = nil
    private(set) var logLines: [String] = []
    /// When the last watch state update from the phone was made.
    private(set) var lastPhoneContact: Date?
    /// The newest glucose the phone has. The phone can still reach the watch
    /// while it has lost the sensor (flight mode keeps the watch link), so
    /// this, not the contact, says whether the phone's glucose is current.
    private(set) var phoneGlucoseDate: Date?

    // MARK: - Private

    @ObservationIgnored private var session: WatchG7Session?
    @ObservationIgnored private var sharedKey: Data?
    @ObservationIgnored private var peripheralIdentifier: UUID?
    private let defaults = UserDefaults.standard
    @ObservationIgnored private var heldBluetoothTask: WKRefreshBackgroundTask?
    @ObservationIgnored private var completedBluetoothTasks: [WKRefreshBackgroundTask] = []

    private static let historyDuration = TimeInterval(hours: 12)
    /// A reading this old still shows on the watch face.
    static let freshReadingAge = TimeInterval(minutes: 11)
    /// The phone counts as gone once its last update is this old.
    static let phoneQuietAfter = TimeInterval(minutes: 10)

    private enum Key {
        static let enabled = "watchG7.enabled"
        static let sensorName = "watchG7.sensorName"
        static let pairingCode = "watchG7.pairingCode"
        static let phoneUsesG7Direct = "watchG7.phoneUsesG7Direct"
        static let units = "watchG7.units"
        static let urgentLow = "watchG7.urgentLowMgDL"
        static let low = "watchG7.lowMgDL"
        static let high = "watchG7.highMgDL"
        static let sharedKey = "watchG7.sharedKey"
        static let peripheralIdentifier = "watchG7.peripheralIdentifier"
        static let history = "watchG7.history"
        static let log = "watchG7.log"
        static let lastAlert = "watchG7.lastAlert."
        static let lastPhoneContact = "watchG7.lastPhoneContact"
        static let phoneGlucoseDate = "watchG7.phoneGlucoseDate"
    }

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Key.enabled)
        sensorName = defaults.string(forKey: Key.sensorName)
        pairingCode = defaults.string(forKey: Key.pairingCode)
        phoneUsesG7Direct = defaults.object(forKey: Key.phoneUsesG7Direct) as? Bool
        units = defaults.string(forKey: Key.units) ?? "mg/dL"
        urgentLowMgDL = defaults.object(forKey: Key.urgentLow) as? Double ?? 54
        lowMgDL = defaults.object(forKey: Key.low) as? Double
        highMgDL = defaults.object(forKey: Key.high) as? Double
        sharedKey = defaults.data(forKey: Key.sharedKey)
        hasWatchKey = defaults.data(forKey: Key.sharedKey) != nil
        peripheralIdentifier = defaults.string(forKey: Key.peripheralIdentifier).flatMap(UUID.init(uuidString:))
        lastPhoneContact = defaults.object(forKey: Key.lastPhoneContact) as? Date
        phoneGlucoseDate = defaults.object(forKey: Key.phoneGlucoseDate) as? Date
        if let data = defaults.data(forKey: Key.history),
           let saved = try? JSONDecoder().decode([WatchG7Reading].self, from: data)
        {
            history = saved
        } else {
            history = []
        }
        // The log survives restarts, so a gap can still be looked at afterwards.
        logLines = defaults.stringArray(forKey: Key.log) ?? []
    }

    // MARK: - Derived values for the views

    var latest: WatchG7Reading? { history.last }

    /// The newest reading if it is recent enough to show.
    var freshReading: WatchG7Reading? {
        guard let latest, Date().timeIntervalSince(latest.date) < Self.freshReadingAge else { return nil }
        return latest
    }

    /// The phone has no current glucose: it is out of reach, or it is in
    /// reach but has lost the sensor. The watch is on its own.
    var phoneGlucoseIsStale: Bool {
        guard let phoneGlucoseDate else { return true }
        return Date().timeIntervalSince(phoneGlucoseDate) > Self.phoneQuietAfter
    }

    /// The watch's own reading when it is newer than what the phone shows:
    /// the phone's data is stale, or the phone has missed a reading the watch got.
    func readingToShow(phoneDataIsDated: Bool) -> WatchG7Reading? {
        guard isEnabled, let fresh = freshReading else { return nil }
        if phoneDataIsDated { return fresh }
        guard let phoneGlucoseDate else { return fresh }
        // Readings are 5 minutes apart: anything 2.5 minutes newer is a reading the phone does not have.
        return fresh.date.timeIntervalSince(phoneGlucoseDate) > TimeInterval(minutes: 2.5) ? fresh : nil
    }

    var isMmol: Bool { units == "mmol/L" }

    func format(_ mgdl: Double) -> String {
        isMmol ? String(format: "%.1f", mgdl * 0.0555) : String(Int(mgdl.rounded()))
    }

    /// The change since the reading about five minutes earlier, formatted.
    var deltaText: String? {
        guard let latest else { return nil }
        let earlier = history.dropLast().last(where: { reading in
            let gap = latest.date.timeIntervalSince(reading.date)
            return gap >= TimeInterval(minutes: 3) && gap <= TimeInterval(minutes: 7)
        })
        guard let previous = earlier else { return nil }
        let delta = Double(latest.glucose - previous.glucose)
        if isMmol {
            return String(format: "%+.1f", delta * 0.0555)
        }
        return String(format: "%+ld", Int(delta))
    }

    /// The watch's own readings over the last two hours: how many of the
    /// possible ones arrived, and the longest stretch without one.
    var recentCoverage: (count: Int, expected: Int, longestGapMinutes: Int) {
        let now = Date()
        let window = TimeInterval(hours: 2)
        let recent = history.filter { now.timeIntervalSince($0.date) <= window }.map(\.date)
        var longest: TimeInterval = 0
        var previous = now.addingTimeInterval(-window)
        for date in recent {
            longest = max(longest, date.timeIntervalSince(previous))
            previous = date
        }
        longest = max(longest, now.timeIntervalSince(previous))
        return (recent.count, Int(window / 300), Int(longest / 60))
    }

    /// One line saying what the watch is doing, for the sensor page.
    var statusText: String {
        guard isEnabled else {
            return String(localized: "Off", comment: "Watch G7 status: the watch does not read the sensor")
        }
        if phoneUsesG7Direct == false, sensorName == nil {
            return String(
                localized: "iPhone isn't on G7 direct",
                comment: "Watch G7 status: the phone is not using G7 direct"
            )
        }
        guard sensorName != nil else {
            return String(
                localized: "Waiting for the iPhone",
                comment: "Watch G7 status: nothing received from the phone yet"
            )
        }
        if pairingCode == nil, !hasWatchKey {
            return String(
                localized: "No pairing code",
                comment: "Watch G7 status: the phone has no pairing code"
            )
        }
        if isConnected {
            return String(localized: "Connected", comment: "Watch G7 status: connected")
        }
        if isSearching {
            return String(
                localized: "Searching… keep this open",
                comment: "Watch G7 status: scanning for a sensor it has not found yet"
            )
        }
        if !hasWatchKey {
            return String(
                localized: "Not paired yet. Accept a pairing prompt.",
                comment: "Watch G7 status: found but not yet paired"
            )
        }
        return String(
            localized: "Waiting for next reading",
            comment: "Watch G7 status: paired and idle between readings"
        )
    }

    // MARK: - Lifecycle

    /// At launch, including a background relaunch for Bluetooth: the central
    /// has to exist again before the system hands back the restored link.
    func bootstrap() {
        dispatchPrecondition(condition: .onQueue(.main))
        if isEnabled {
            startSessionIfPossible()
        }
    }

    /// Any wake: a lost Bluetooth callback can leave nothing waiting for the sensor.
    func noteWake() {
        session?.recheck()
    }

    /// Asks watchOS for a background wake about every 15 minutes (it decides
    /// the actual timing). Each wake re-checks the sensor connection, so a
    /// request the system dropped is put back without the app being opened.
    func scheduleBackgroundRefresh() {
        guard isEnabled else { return }
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date().addingTimeInterval(TimeInterval(minutes: 15)),
            userInfo: nil
        ) { _ in }
    }

    func setEnabled(_ enabled: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.enabled)
        if enabled {
            appendLog("Turned on")
            requestNotificationPermission()
            startSessionIfPossible()
            scheduleBackgroundRefresh()
        } else {
            appendLog("Turned off")
            session?.pause()
            isConnected = false
            isSearching = false
        }
    }

    /// Forgets the watch's own pairing with the sensor; the next connection pairs again.
    func resetWatchPairing() {
        dispatchPrecondition(condition: .onQueue(.main))
        appendLog("Pairing reset on the watch")
        setSharedKey(nil)
        setPeripheralIdentifier(nil)
        session?.update(credentials: credentials)
    }

    private var credentials: WatchG7Credentials {
        WatchG7Credentials(
            sensorName: sensorName,
            pairingCode: pairingCode,
            sharedKey: sharedKey,
            peripheralIdentifier: peripheralIdentifier
        )
    }

    private func startSessionIfPossible() {
        guard isEnabled, sensorName != nil else { return }
        if let session {
            session.update(credentials: credentials)
            session.resume()
        } else {
            let session = WatchG7Session(credentials: credentials, latestReadingDate: latest?.date)
            session.delegate = self
            self.session = session
            appendLog("Starting")
            session.resume()
        }
    }

    // MARK: - From the phone

    /// Called with every watch state update the phone sends.
    func updateFromPhone(_ payload: [String: Any]) {
        dispatchPrecondition(condition: .onQueue(.main))
        // Every phone update is also a wake: re-check the sensor connection.
        noteWake()

        if let timestamp = payload[WatchMessageKeys.date] as? TimeInterval {
            let date = Date(timeIntervalSince1970: timestamp)
            if date > (lastPhoneContact ?? .distantPast) {
                lastPhoneContact = date
                defaults.set(date, forKey: Key.lastPhoneContact)
            }
        }

        if let values = payload[WatchMessageKeys.glucoseValues] as? [[String: Any]],
           let newest = values.compactMap({ $0["date"] as? TimeInterval }).max()
        {
            let date = Date(timeIntervalSince1970: newest)
            phoneGlucoseDate = date
            defaults.set(date, forKey: Key.phoneGlucoseDate)
            session?.notePhoneReading(at: date)
        }

        // Units from the dedicated key; the general one only from a state with
        // glucose in it, because an empty default state says mg/dL.
        let hasGlucose = !((payload[WatchMessageKeys.glucoseValues] as? [[String: Any]])?.isEmpty ?? true)
        let sentUnits = payload[WatchMessageKeys.watchDisplayUnits] as? String
            ?? (hasGlucose ? payload[WatchMessageKeys.units] as? String : nil)
        if let units = sentUnits, units != self.units {
            self.units = units
            defaults.set(units, forKey: Key.units)
        }
        if let value = payload[WatchMessageKeys.watchAlertUrgentLowMgDL] as? Double, value > 0 {
            urgentLowMgDL = value
            defaults.set(value, forKey: Key.urgentLow)
        }
        if let value = payload[WatchMessageKeys.watchAlertLowMgDL] as? Double {
            lowMgDL = value > 0 ? value : nil
            defaults.set(lowMgDL, forKey: Key.low)
        }
        if let value = payload[WatchMessageKeys.watchAlertHighMgDL] as? Double {
            highMgDL = value > 0 ? value : nil
            defaults.set(highMgDL, forKey: Key.high)
        }

        // An empty name means the phone is not reading a G7 directly. Keep what
        // the watch already has: a brief switch on the phone should not make
        // the watch forget a sensor it can still read.
        guard let name = payload[WatchMessageKeys.g7DirectSensorName] as? String else { return }
        let usesDirect = !name.isEmpty
        if phoneUsesG7Direct != usesDirect {
            phoneUsesG7Direct = usesDirect
            defaults.set(usesDirect, forKey: Key.phoneUsesG7Direct)
        }
        guard usesDirect else { return }

        let code = (payload[WatchMessageKeys.g7DirectPairingCode] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var credentialsChanged = false

        if name.suffix(2) != sensorName?.suffix(2) {
            if sensorName != nil {
                appendLog("New sensor \(name) from the iPhone")
            }
            sensorName = name
            defaults.set(name, forKey: Key.sensorName)
            // A different sensor: the watch's key and peripheral belong to the old one.
            setSharedKey(nil)
            setPeripheralIdentifier(nil)
            history = []
            saveHistory()
            credentialsChanged = true
        }
        if let code, code != pairingCode {
            if pairingCode != nil, hasWatchKey {
                // A new code means a new sensor, even if its name ends the same.
                setSharedKey(nil)
                setPeripheralIdentifier(nil)
            }
            pairingCode = code
            defaults.set(code, forKey: Key.pairingCode)
            credentialsChanged = true
        }

        if credentialsChanged {
            startSessionIfPossible()
        }
    }

    // MARK: - Background Bluetooth wakes

    /// A wake the system granted because the sensor's link delivered something.
    /// Held for 25 seconds so the reading can arrive, then completed exactly once.
    func hold(bluetoothTask task: WKRefreshBackgroundTask) {
        dispatchPrecondition(condition: .onQueue(.main))
        noteWake()
        if let held = heldBluetoothTask, held !== task {
            // One held per wake; the rest are completed on arrival.
            complete(task)
            return
        }
        heldBluetoothTask = task
        task.expirationHandler = { [weak self] in
            DispatchQueue.main.async { self?.completeHeldBluetoothTask(task) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            self?.completeHeldBluetoothTask(task)
        }
    }

    private func completeHeldBluetoothTask(_ task: WKRefreshBackgroundTask) {
        guard heldBluetoothTask === task else { return }
        heldBluetoothTask = nil
        complete(task)
    }

    private func complete(_ task: WKRefreshBackgroundTask) {
        // Completing a task twice throws inside WatchKit.
        guard !completedBluetoothTasks.contains(where: { $0 === task }) else { return }
        completedBluetoothTasks.append(task)
        if completedBluetoothTasks.count > 64 {
            completedBluetoothTasks.removeFirst(16)
        }
        task.setTaskCompletedWithSnapshot(false)
    }

    // MARK: - Persistence helpers

    private func setSharedKey(_ key: Data?) {
        sharedKey = key
        hasWatchKey = key != nil
        defaults.set(key, forKey: Key.sharedKey)
    }

    private func setPeripheralIdentifier(_ identifier: UUID?) {
        peripheralIdentifier = identifier
        defaults.set(identifier?.uuidString, forKey: Key.peripheralIdentifier)
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Key.history)
        }
    }

    private func merge(_ readings: [WatchG7Reading]) {
        var merged = history
        for reading in readings where !merged.contains(where: { abs($0.date.timeIntervalSince(reading.date)) < 60 }) {
            merged.append(reading)
        }
        let cutoff = Date().addingTimeInterval(-Self.historyDuration)
        history = merged.filter { $0.date > cutoff }.sorted { $0.date < $1.date }
        saveHistory()
    }

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm:ss"
        logLines.append("\(formatter.string(from: Date())) \(line)")
        if logLines.count > 200 {
            logLines.removeFirst(logLines.count - 200)
        }
        defaults.set(logLines, forKey: Key.log)
        Task {
            await WatchLogger.shared.log("⌚️🩸 G7: \(line)")
        }
    }

    // MARK: - Alerts

    private enum AlertKind: String {
        case urgentLow
        case low
        case high

        var repeatInterval: TimeInterval {
            switch self {
            case .urgentLow: return TimeInterval(minutes: 5)
            case .low: return TimeInterval(minutes: 15)
            case .high: return TimeInterval(minutes: 60)
            }
        }

        var title: String {
            switch self {
            case .urgentLow: return String(localized: "Urgent Low", comment: "Watch G7 alert title")
            case .low: return String(localized: "Low Glucose", comment: "Watch G7 alert title")
            case .high: return String(localized: "High Glucose", comment: "Watch G7 alert title")
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if !granted {
                DispatchQueue.main.async {
                    self.appendLog("Notifications are not allowed for Trio on the watch; alerts will not show")
                }
            }
        }
    }

    /// Alerts only while the phone has no current glucose: when it has, Trio's
    /// own alarms already reach the wrist.
    private func evaluateAlerts(for reading: WatchG7Reading) {
        guard phoneGlucoseIsStale, Date().timeIntervalSince(reading.date) < Self.freshReadingAge else { return }
        let glucose = Double(reading.glucose)
        let margin = 5.0

        if glucose <= urgentLowMgDL {
            fire(.urgentLow, reading: reading)
        } else if glucose > urgentLowMgDL + margin {
            clear(.urgentLow)
        }

        if let low = lowMgDL {
            if glucose <= low, glucose > urgentLowMgDL {
                fire(.low, reading: reading)
            } else if glucose > low + margin {
                clear(.low)
            }
        }

        if let high = highMgDL {
            if glucose >= high {
                fire(.high, reading: reading)
            } else if glucose < high - margin {
                clear(.high)
            }
        }
    }

    private func fire(_ kind: AlertKind, reading: WatchG7Reading) {
        let key = Key.lastAlert + kind.rawValue
        if let last = defaults.object(forKey: key) as? Date, Date().timeIntervalSince(last) < kind.repeatInterval {
            return
        }
        defaults.set(Date(), forKey: key)

        let content = UNMutableNotificationContent()
        content.title = kind.title
        let value = "\(format(Double(reading.glucose))) \(units) \(arrow(for: reading.trendName))"
        content.body = String(
            format: String(
                localized: "%@ · read by your watch. No data from the iPhone.",
                comment: "Watch G7 alert body (1: glucose with units and trend arrow)"
            ),
            value
        )
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifierPrefix + kind.rawValue,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        WKInterfaceDevice.current().play(kind == .high ? .notification : .failure)
        appendLog("Alert: \(kind.title) \(value)")
    }

    private func clear(_ kind: AlertKind) {
        let key = Key.lastAlert + kind.rawValue
        guard defaults.object(forKey: key) != nil else { return }
        defaults.removeObject(forKey: key)
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [Self.notificationIdentifierPrefix + kind.rawValue]
        )
    }

    static let notificationIdentifierPrefix = "trio.watchG7."

    func arrow(for trendName: String?) -> String {
        switch trendName {
        case "DoubleUp": return "⇈"
        case "SingleUp": return "↑"
        case "FortyFiveUp": return "↗"
        case "Flat": return "→"
        case "FortyFiveDown": return "↘"
        case "SingleDown": return "↓"
        case "DoubleDown": return "⇊"
        default: return ""
        }
    }

    // MARK: - WatchG7SessionDelegate (called on the session's queue)

    func session(_: WatchG7Session, didRead message: WatchG7GlucoseMessage, receivedAt: Date) {
        DispatchQueue.main.async {
            guard message.hasReliableGlucose, let glucose = message.glucose else {
                let problem = String(describing: message.algorithmState)
                self.sensorProblem = problem
                self.appendLog("Sensor answered without a reading (\(problem))")
                return
            }
            self.sensorProblem = nil
            let reading = WatchG7Reading(
                date: receivedAt.addingTimeInterval(-TimeInterval(message.age)),
                glucose: Int(glucose),
                trendRate: message.trend
            )
            self.merge([reading])
            self.appendLog("Reading \(self.format(Double(reading.glucose))) \(self.units) \(self.arrow(for: reading.trendName))")
            self.evaluateAlerts(for: reading)
        }
    }

    func session(_: WatchG7Session, didReadBackfill readings: [WatchG7Reading]) {
        DispatchQueue.main.async {
            self.merge(readings)
            self.appendLog("Filled in \(readings.count) missed readings")
        }
    }

    func session(_: WatchG7Session, didAuthenticateWith sharedKey: Data) {
        DispatchQueue.main.async {
            self.setSharedKey(sharedKey)
            self.appendLog("Paired with the sensor")
        }
    }

    func sessionDidInvalidateSharedKey(_: WatchG7Session) {
        DispatchQueue.main.async {
            self.setSharedKey(nil)
        }
    }

    func session(_: WatchG7Session, didAdoptPeripheral identifier: UUID?) {
        DispatchQueue.main.async {
            self.setPeripheralIdentifier(identifier)
        }
    }

    func session(_: WatchG7Session, log line: String) {
        DispatchQueue.main.async {
            self.appendLog(line)
        }
    }

    func session(_: WatchG7Session, didChangeConnection connected: Bool) {
        DispatchQueue.main.async {
            self.isConnected = connected
        }
    }

    func sessionStatusDidChange(_ session: WatchG7Session) {
        let searching = session.isSearchingForSensor
        let needsCode = session.needsCodeForSensor
        DispatchQueue.main.async {
            self.isSearching = searching
            self.needsCodeForSensor = needsCode
        }
    }
}
