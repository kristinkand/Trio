import Combine
import CoreData
import Observation
import SwiftUI

extension Adjustments {
    @Observable final class StateModel: BaseStateModel<Provider> {
        // MARK: - Injected Dependencies

        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() var tempTargetStorage: TempTargetsStorage!
        @ObservationIgnored @Injected() var apsManager: APSManager!
        @ObservationIgnored @Injected() var overrideStorage: OverrideStorage!
        @ObservationIgnored @Injected() var nightscoutManager: NightscoutManager!

        var requireAdjustmentsConfirmation: Bool = false
        var shouldDisplayPresetStartConfirmDialog: Bool = false

        // MARK: - Override and Temp Target Properties

        var overridePercentage: Double = 100
        var isOverrideEnabled = false
        var indefinite = true
        var overrideDuration: Decimal = 0
        var target: Decimal = 0
        var currentGlucoseTarget: Decimal = 100
        var shouldOverrideTarget: Bool = false
        var smbIsOff: Bool = false
        var id = ""
        var overrideName: String = ""
        var isPreset: Bool = false
        var overridePresets: [OverrideStored] = []
        var advancedSettings: Bool = false
        var isfAndCr: Bool = true
        var isf: Bool = true
        var cr: Bool = true
        var smbIsScheduledOff: Bool = false
        var start: Decimal = 0
        var end: Decimal = 0
        var smbMinutes: Decimal = 0
        var uamMinutes: Decimal = 0
        var defaultSmbMinutes: Decimal = 0
        var defaultUamMinutes: Decimal = 0
        var selectedTab: Tab = .overrides
        var activeOverrideName: String = ""
        var currentActiveOverride: OverrideStored?
        var activeTempTargetName: String = ""

        var currentActiveTempTarget: TempTargetStored?
        var showOverrideEditSheet = false
        var showTempTargetEditSheet = false
        var units: GlucoseUnits = .mgdL

        // Temp Target Properties
        var tempTargetDuration: Decimal = 0
        var tempTargetName: String = ""
        var tempTargetTarget: Decimal = 100
        var isTempTargetEnabled: Bool = false
        var date = Date()
        var newPresetName = ""
        var tempTargetPresets: [TempTargetStored] = []
        var scheduledTempTargets: [TempTargetStored] = []
        var percentage: Double = 100
        var autosensMax: Decimal = 1.2
        var halfBasalTarget: Decimal = 160
        var settingHalfBasalTarget: Decimal = 160
        var highTTraisesSens: Bool = false
        var isExerciseModeActive: Bool = false
        var lowTTlowersSens: Bool = false
        var didSaveSettings: Bool = false

        // Core Data
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        // Help Sheet
        var isHelpSheetPresented: Bool = false
        var helpSheetDetent = PresentationDetent.large

        // Combine
        private var cancellables = Set<AnyCancellable>()

        // MARK: - Lifecycle

        /// Subscribes to notifications and initializes settings.
        override func subscribe() {
            setupNotification()
            setupSettings()
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PreferencesObserver.self, observer: self)

            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { self.setupOverridePresetsArray() }
                    group.addTask { self.setupTempTargetPresetsArray() }
                    group.addTask { self.updateLatestOverrideConfiguration() }
                    group.addTask { self.updateLatestTempTargetConfiguration() }
                }
            }
        }

        /// Retrieves the current glucose target based on the time of day.
        func getCurrentGlucoseTarget() async {
            let bgTargets = await provider.getBGTargets()
            if let currentTarget = bgTargets.currentTarget() {
                await MainActor.run {
                    currentGlucoseTarget = currentTarget
                    target = currentGlucoseTarget
                }
            }
        }

        /// Configures various settings from the settings manager.
        private func setupSettings() {
            units = settingsManager.settings.units
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            autosensMax = settingsManager.preferences.autosensMax
            settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
            halfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
            highTTraisesSens = settingsManager.preferences.highTemptargetRaisesSensitivity
            isExerciseModeActive = settingsManager.preferences.exerciseMode
            lowTTlowersSens = settingsManager.preferences.lowTemptargetLowersSensitivity
            percentage = TempTargetCalculations.computeAdjustedPercentage(
                halfBasalTarget: halfBasalTarget,
                target: tempTargetTarget,
                autosensMax: autosensMax
            )
            requireAdjustmentsConfirmation = settingsManager.settings.requireAdjustmentsConfirmation
            Task {
                await getCurrentGlucoseTarget()
            }
        }

        /// Reorders Override Presets and updates the view.
        func reorderOverride(from source: IndexSet, to destination: Int) {
            overridePresets.move(fromOffsets: source, toOffset: destination)
            for (index, override) in overridePresets.enumerated() {
                override.orderPosition = Int16(index + 1)
            }
            Task {
                do {
                    guard viewContext.hasChanges else { return }
                    try viewContext.save()
                    setupOverridePresetsArray()
                    try await nightscoutManager.uploadProfiles()
                } catch {
                    debugPrint(
                        "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Override Presets order or upload profiles"
                    )
                }
            }
        }

        /// Reorders Temp Target Presets and updates the view.
        func reorderTempTargets(from source: IndexSet, to destination: Int) {
            tempTargetPresets.move(fromOffsets: source, toOffset: destination)
            for (index, tempTarget) in tempTargetPresets.enumerated() {
                tempTarget.orderPosition = Int16(index + 1)
            }
            do {
                guard viewContext.hasChanges else { return }
                try viewContext.save()
                setupTempTargetPresetsArray()
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Temp Target Presets order")
            }
        }
    }
}

// MARK: - Notifications Setup

extension Adjustments.StateModel {
    /// Sets up notification observers for Override and Temp Target updates.
    func setupNotification() {
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOverrideConfigurationUpdate),
            name: .didUpdateOverrideConfiguration,
            object: nil
        )

        // Custom Notification to update View when an Temp Target has been cancelled via Home View
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTempTargetConfigurationUpdate),
            name: .didUpdateTempTargetConfiguration,
            object: nil
        )

        // Creates a publisher that updates the Override View when the Custom notification was sent (via shortcut)
        Foundation.NotificationCenter.default.publisher(for: .willUpdateOverrideConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateLatestOverrideConfiguration()
            }
            .store(in: &cancellables)

        // Creates a publisher that updates the Temp Target View when the Custom notification was sent (via shortcut)
        Foundation.NotificationCenter.default.publisher(for: .willUpdateTempTargetConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateLatestTempTargetConfiguration()
            }
            .store(in: &cancellables)
    }

    /// Handles Override configuration updates.
    @objc private func handleOverrideConfigurationUpdate() {
        updateLatestOverrideConfiguration()
    }

    /// Handles Temp Target configuration updates.
    @objc private func handleTempTargetConfigurationUpdate() {
        updateLatestTempTargetConfiguration()
    }
}

extension Adjustments.StateModel: SettingsObserver, PreferencesObserver {
    /// Updates settings when they change.
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
        requireAdjustmentsConfirmation = settingsManager.settings.requireAdjustmentsConfirmation
        Task {
            await getCurrentGlucoseTarget()
        }
    }

    /// Updates preferences when they change.
    func preferencesDidChange(_: Preferences) {
        defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
        defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
        autosensMax = settingsManager.preferences.autosensMax
        settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
        halfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
        highTTraisesSens = settingsManager.preferences.highTemptargetRaisesSensitivity
        isExerciseModeActive = settingsManager.preferences.exerciseMode
        lowTTlowersSens = settingsManager.preferences.lowTemptargetLowersSensitivity
        percentage = TempTargetCalculations.computeAdjustedPercentage(
            halfBasalTarget: halfBasalTarget,
            target: tempTargetTarget,
            autosensMax: autosensMax
        )
        Task {
            await getCurrentGlucoseTarget()
        }
    }

    /// Starts Weekend Profile: records the real start time -- both locally, so the run can be
    /// anchored in History > Adjustments and its real duration computed when it's stopped, and on
    /// Nightscout, as an "Exercise" event (Trio's own Override eventType) with an indefinite
    /// ~30-day duration. Reusing "Exercise" means Loop Follow (and any Nightscout-based viewer that
    /// already understands Trio Overrides) picks this up automatically, with the profile's name as
    /// the note; `weekendProfileEnteredBy` is a marker distinct from a real Override's "Trio" so it
    /// can still be told apart downstream and shown with its own color.
    func startWeekendProfile() {
        let start = Date()
        WeekendProfileStore.activeStartDate = start
        Task {
            let event = NightscoutExercise(
                duration: weekendProfileIndefiniteDurationMinutes,
                eventType: .nsExercise,
                createdAt: start,
                enteredBy: weekendProfileEnteredBy,
                notes: WeekendProfileStore.name
            )
            await nightscoutManager.uploadWeekendProfileEvent(event, replacingPrevious: false)
        }
    }

    /// Stops Weekend Profile: records the completed run locally (so it's anchored in History >
    /// Adjustments with its real start/end, like an Override or Temp Target) and corrects the
    /// Nightscout entry `startWeekendProfile` posted from its indefinite duration to the real
    /// elapsed one, so Loop Follow (and any other Nightscout-based viewer) shows the real end time
    /// instead of ~30 days out.
    func stopWeekendProfile() {
        let end = Date()
        let name = WeekendProfileStore.name
        guard let start = WeekendProfileStore.activeStartDate else {
            // Nothing to close out -- e.g. Weekend Profile was already active before this version's
            // start-tracking existed. Nothing was recorded to correct on Nightscout either.
            return
        }
        WeekendProfileStore.activeStartDate = nil
        WeekendProfileStore.recordCompletedRun(name: name, start: start, end: end)

        let elapsedMinutes = max(1, Int(end.timeIntervalSince(start) / 60))
        Task {
            let event = NightscoutExercise(
                duration: elapsedMinutes,
                eventType: .nsExercise,
                createdAt: start,
                enteredBy: weekendProfileEnteredBy,
                notes: name
            )
            await nightscoutManager.uploadWeekendProfileEvent(event, replacingPrevious: true)
        }
    }
}

/// Trio represents an indefinite Override as a ~30-day (43200 minute) duration (see
/// `OverrideStorage.getOverrideRunsNotYetUploadedToNightscout`); Weekend Profile's start posting
/// matches that convention so downstream viewers already treat it as "ongoing, no known end".
private let weekendProfileIndefiniteDurationMinutes = 43200
/// Distinguishes a Weekend Profile run from a real Override on Nightscout even though both share
/// the "Exercise" eventType and Trio's usual `enteredBy` of "Trio".
private let weekendProfileEnteredBy = "Trio Weekend Profile"

// MARK: - Weekend Profile

extension Adjustments.StateModel {
    /// The real basal schedule, exposed only so `WeekendProfileSection` can prefill its own draft
    /// the first time the editor is opened (see `WeekendProfileStore.isConfigured`). Never written
    /// to -- Weekend Profile's schedule lives entirely in `WeekendProfileStore`.
    var currentBasalProfileForWeekendPrefill: [BasalProfileEntry] { provider.currentBasalProfile }

    /// The real ISF schedule -- same prefill purpose as `currentBasalProfileForWeekendPrefill`.
    var currentInsulinSensitivitiesForWeekendPrefill: InsulinSensitivities { provider.currentInsulinSensitivities }

    /// Basal rate values Weekend Profile's schedule editor is allowed to offer. Prefers the
    /// connected pump's real supported increments (same source the real Basal Profile Editor
    /// uses) so a Weekend schedule can't drift from what the pump can actually approximate; falls
    /// back to the same generous default the real editor uses when no pump is connected. Either
    /// way, capped at the user's configured Max Basal safety setting -- that's an independent
    /// ceiling from what the pump can mechanically do, and Weekend Profile's substituted schedule
    /// feeds `currentBasal`/`maxDailyBasal` in the dosing algorithm (see `OpenAPS.createProfiles()`
    /// and `TempBasalFunctions.getMaxSafeBasalRate()`), so keeping the raw schedule values
    /// themselves within Max Basal avoids skewing that math even though delivered temp basals were
    /// always separately capped there regardless.
    var weekendBasalRateValues: [Decimal] {
        let values = provider.supportedBasalRates
            ?? stride(from: 5.0, to: 1001.0, by: 5.0).map { (Decimal($0)) / 100 }
        let maxBasal = provider.maxBasalRate
        let capped = values.filter { $0 <= maxBasal }
        // Never return an empty list -- if Max Basal is set below every available increment,
        // offering the uncapped list is safer than leaving the picker with no options at all.
        return capped.isEmpty ? values : capped
    }

    /// Persists a full Weekend Profile draft in one shot -- the only place that writes
    /// `WeekendProfileStore`'s configurable fields, called from `WeekendProfileSection`'s Save
    /// button. Also posts a Nightscout Note so a schedule change is visible on the chart, and marks
    /// the profile as configured so the next time the editor opens it loads these saved values
    /// instead of prefilling from real settings again.
    func saveWeekendProfile(
        name: String,
        target: Decimal,
        smbMinutes: Decimal,
        uamMinutes: Decimal,
        basalProfile: [BasalProfileEntry],
        insulinSensitivities: InsulinSensitivities
    ) {
        WeekendProfileStore.name = name
        WeekendProfileStore.target = target
        WeekendProfileStore.smbMinutes = smbMinutes
        WeekendProfileStore.uamMinutes = uamMinutes
        WeekendProfileStore.basalProfile = basalProfile
        WeekendProfileStore.insulinSensitivities = insulinSensitivities
        let wasConfigured = WeekendProfileStore.isConfigured
        WeekendProfileStore.isConfigured = true
        Foundation.NotificationCenter.default.post(name: .didUpdateWeekendProfileConfiguration, object: nil)

        Task {
            await nightscoutManager.uploadNoteTreatment(
                note: wasConfigured ? "\(name) updated" : "\(name) configured"
            )
        }
    }
}
