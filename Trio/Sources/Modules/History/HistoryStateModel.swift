import CoreData
import HealthKit
import Observation
import SwiftUI

extension History {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() var apsManager: APSManager!
        @ObservationIgnored @Injected() var unlockmanager: UnlockManager!
        @ObservationIgnored @Injected() private var storage: FileStorage!
        @ObservationIgnored @Injected() var pumpHistoryStorage: PumpHistoryStorage!
        @ObservationIgnored @Injected() var glucoseStorage: GlucoseStorage!
        @ObservationIgnored @Injected() var healthKitManager: HealthKitManager!
        @ObservationIgnored @Injected() var carbsStorage: CarbsStorage!
        @ObservationIgnored @Injected() var placementLogStorage: PlacementLogStorage!

        var mode: Mode = .treatments
        var treatments: [Treatment] = []
        var manualGlucose: Decimal = 0
        var waitForSuggestion: Bool = false

        var insulinEntryDeleted: Bool = false
        var carbEntryDeleted: Bool = false

        var units: GlucoseUnits = .mgdL

        var carbEntryToEdit: CarbEntryStored?
        var showCarbEntryEditor = false

        var newPlacementDate: Date = Date()
        var newPlacementDeviceType: PlacementDeviceType = .pump
        var newPlacementLocation: PlacementLocation = .abdomenLeftHigh
        var newPlacementHasSiteIssue: Bool = false
        var newPlacementIsPainful: Bool = false
        var newPlacementIsPainfulGivingInsulin: Bool = false
        var newPlacementHasInaccurateReadings: Bool = false
        var editingPlacementLogObjectID: NSManagedObjectID?

        override func subscribe() {
            units = settingsManager.settings.units
            broadcaster.register(DeterminationObserver.self, observer: self)
            broadcaster.register(SettingsObserver.self, observer: self)
        }

        /// Checks if the glucose data is fresh based on the given date
        /// - Parameter glucoseDate: The date to check
        /// - Returns: Boolean indicating if the data is fresh
        func isGlucoseDataFresh(_ glucoseDate: Date?) -> Bool {
            glucoseStorage.isGlucoseDataFresh(glucoseDate)
        }

        func addManualGlucose() {
            // Always save value in mg/dL
            let glucose = units == .mmolL ? manualGlucose.asMgdL : manualGlucose
            let glucoseAsInt = Int(glucose)

            glucoseStorage.addManualGlucose(glucose: glucoseAsInt)
        }

        func startEditingPlacementLog(_ entry: PlacementLogStored) {
            editingPlacementLogObjectID = entry.objectID
            newPlacementDate = entry.date ?? Date()
            newPlacementDeviceType = entry.deviceTypeEnum
            newPlacementLocation = entry.locationEnum
            newPlacementHasSiteIssue = entry.hasSiteIssue
            newPlacementIsPainful = entry.isPainful
            newPlacementIsPainfulGivingInsulin = entry.isPainfulGivingInsulin
            newPlacementHasInaccurateReadings = entry.hasInaccurateReadings
        }

        func resetNewPlacementLogFields() {
            editingPlacementLogObjectID = nil
            newPlacementDate = Date()
            newPlacementDeviceType = .pump
            newPlacementLocation = .abdomenLeftHigh
            newPlacementHasSiteIssue = false
            newPlacementIsPainful = false
            newPlacementIsPainfulGivingInsulin = false
            newPlacementHasInaccurateReadings = false
        }

        func savePlacementLog() {
            Task {
                if let objectID = editingPlacementLogObjectID {
                    await placementLogStorage.updatePlacementLog(
                        objectID,
                        date: newPlacementDate,
                        deviceType: newPlacementDeviceType,
                        location: newPlacementLocation,
                        hasSiteIssue: newPlacementHasSiteIssue,
                        isPainful: newPlacementIsPainful,
                        isPainfulGivingInsulin: newPlacementIsPainfulGivingInsulin,
                        hasInaccurateReadings: newPlacementHasInaccurateReadings
                    )
                } else {
                    await placementLogStorage.addPlacementLog(
                        date: newPlacementDate,
                        deviceType: newPlacementDeviceType,
                        location: newPlacementLocation,
                        hasSiteIssue: newPlacementHasSiteIssue,
                        isPainful: newPlacementIsPainful,
                        isPainfulGivingInsulin: newPlacementIsPainfulGivingInsulin,
                        hasInaccurateReadings: newPlacementHasInaccurateReadings
                    )
                }
                resetNewPlacementLogFields()
            }
        }

        func deletePlacementLog(_ objectID: NSManagedObjectID) {
            Task {
                await placementLogStorage.deletePlacementLog(objectID)
            }
        }
    }
}

extension History.StateModel: DeterminationObserver, SettingsObserver {
    func determinationDidUpdate(_: Determination) {
        DispatchQueue.main.async {
            self.waitForSuggestion = false
        }
    }

    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
