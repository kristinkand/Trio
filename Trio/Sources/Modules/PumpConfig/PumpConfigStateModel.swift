import Foundation
import LoopKit
import LoopKitUI
import SwiftDate
import SwiftUI

extension PumpConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var setupPump = false
        private(set) var setupPumpEntry: PumpCatalogEntry?
        @Published var pumpState: PumpDisplayState?
        private(set) var initialSettings: PumpInitialSettings = .default
        @Injected() var bluetoothManager: BluetoothStateManager!
        @Injected() var logExport: LogExport!
        @Published var podChangeBolusEnabled: Bool = false
        @Published var podChangeBolusUnits: Decimal = 0.3
        static let podChangeBolusChoices: [Decimal] = [0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5]

        override func subscribe() {
            subscribeSetting(\.podChangeBolusEnabled, on: $podChangeBolusEnabled) { podChangeBolusEnabled = $0
            } didSet: { enabled in
                PodChangeBolus.noteEnabled(enabled)
            }
            subscribeSetting(\.podChangeBolusUnits, on: $podChangeBolusUnits) { podChangeBolusUnits = $0 }
            provider.pumpDisplayState
                .receive(on: DispatchQueue.main)
                .assign(to: \.pumpState, on: self)
                .store(in: &lifetime)
            Task {
                let basalSchedule = BasalRateSchedule(
                    dailyItems: await provider.getBasalProfile().map {
                        RepeatingScheduleValue(
                            startTime: $0.minutes.minutes.timeInterval,
                            value: Double($0.rate).roundedDouble(toPlaces: 3)
                        )
                    }
                )

                let pumpSettings = provider.pumpSettings()

                await MainActor.run {
                    initialSettings = PumpInitialSettings(
                        maxBolusUnits: Double(pumpSettings.maxBolus),
                        maxBasalRateUnitsPerHour: Double(pumpSettings.maxBasal),
                        basalSchedule: basalSchedule!
                    )
                }
            }
        }

        func addPump(_ entry: PumpCatalogEntry) {
            setupPumpEntry = entry
            setupPump = true
        }
    }
}

extension PumpConfig.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}

extension PumpConfig.StateModel: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        provider.setPumpManager(pumpManager)
        if let insulinType = pumpManager.status.insulinType {
            settingsManager.updateInsulinCurve(insulinType)
        }
    }

    func pumpManagerOnboarding(didOnboardPumpManager _: PumpManagerUI) {
        // nothing to do
    }

    func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {
        // TODO:
    }
}
