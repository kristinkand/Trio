import Foundation

/// A manual "second profile" toggle, independent of Trio's Overrides system, that runs either
/// indefinitely until stopped by hand or -- since `indefinite`/`durationMinutes`/`useSpecificDate`/
/// `scheduledEndDate` were added -- ends itself, either a chosen number of hours after it starts or
/// at a chosen absolute date/time (see `isExpired`/`expireIfNeeded`). Turning it on
/// swaps in its own full time-of-day BASAL and ISF schedules (the exact same `[BasalProfileEntry]` /
/// `InsulinSensitivities` types the real Basal Profile Editor / ISF Editor use), plus an optional BG
/// target and SMB/UAM minutes -- via `OpenAPS.createProfiles()` (basal/ISF) and
/// `OpenAPS.prepareTrioCustomOrefVariables` (target/SMB/UAM minutes). Carb ratio is deliberately
/// never touched here -- there is no `carbRatios` field at all, so CR always comes from the normal
/// settings.
///
/// Unlike an Override:
///   - It's meant for stretches you start yourself (a weekend, a vacation), not just a single loop
///     cycle's duration -- and unless you opt into a duration, it stays on until you stop it,
///     rather than defaulting to a short window the way an Override typically would.
///   - It never blocks a real Override or Temp Target from running. Whenever either is active, it
///     fully takes over the dosing math and Weekend Profile is ignored, automatically resuming the
///     moment the Override/Temp Target ends -- so e.g. a low-glucose-recovery Override still works
///     exactly as it always has, any time, regardless of whether Weekend Profile is on.
///
/// Backed by UserDefaults (not Core Data) since it's a single global on/off setting with no
/// history, presets, or Nightscout sync to manage -- same pattern as the Food Impact override
/// stores in `MealImpactSetup.swift`. Values are clamped to the same safe ranges Trio's own
/// Override editor uses, as defense in depth beyond whatever UI writes them.
enum WeekendProfileStore {
    private static let defaults = UserDefaults.standard

    private static let isActiveKey = "weekendProfileIsActive"
    private static let isConfiguredKey = "weekendProfileIsConfigured"
    private static let activeStartDateKey = "weekendProfileActiveStartDate"
    private static let runHistoryKey = "weekendProfileRunHistory"
    private static let nameKey = "weekendProfileName"
    private static let targetKey = "weekendProfileTarget"
    private static let smbMinutesKey = "weekendProfileSMBMinutes"
    private static let uamMinutesKey = "weekendProfileUAMMinutes"
    private static let basalProfileKey = "weekendProfileBasalProfileData"
    private static let insulinSensitivitiesKey = "weekendProfileInsulinSensitivitiesData"
    private static let indefiniteKey = "weekendProfileIndefinite"
    private static let durationMinutesKey = "weekendProfileDurationMinutes"
    private static let useSpecificDateKey = "weekendProfileUseSpecificDate"
    private static let scheduledEndDateKey = "weekendProfileScheduledEndDate"

    private static let targetRange: ClosedRange<Decimal> = 72 ... 270
    private static let minutesRange: ClosedRange<Decimal> = 0 ... 180
    // Up to 4 days -- generous enough for a long weekend/short vacation while still bounded; see
    // `isExpired` for how this is actually enforced.
    private static let durationRange: ClosedRange<Decimal> = 0 ... 5760

    /// Whether Weekend Profile is currently on. Defaults to `false`.
    static var isActive: Bool {
        get { defaults.bool(forKey: isActiveKey) }
        set { defaults.set(newValue, forKey: isActiveKey) }
    }

    /// False until the editor has been saved once. Gates two things: the algorithm-side schedule
    /// swap in `OpenAPS.createProfiles()` (never substitute an empty/never-chosen schedule), and
    /// the UI's one-time prefill-from-real-settings behavior -- the first time someone opens the
    /// editor, basal/ISF/SMB/UAM start out as copies of their real settings rather than empty or
    /// hardcoded defaults, ready to be tweaked for the weekend.
    static var isConfigured: Bool {
        get { defaults.bool(forKey: isConfiguredKey) }
        set { defaults.set(newValue, forKey: isConfiguredKey) }
    }

    /// When the current (in-progress) run started, i.e. the moment `isActive` last flipped to
    /// `true`. `nil` while inactive. Kept separate from `isActive` so a completed run's exact
    /// start/end can be recorded in `runHistory` -- and the matching Nightscout entry corrected to
    /// its real duration -- once it's stopped. Survives app relaunch since it's UserDefaults-backed.
    static var activeStartDate: Date? {
        get { defaults.object(forKey: activeStartDateKey) as? Date }
        set { defaults.set(newValue, forKey: activeStartDateKey) }
    }

    /// Whether the current/next run should end on its own after `durationMinutes` elapses, instead
    /// of running until manually stopped. Defaults to `true` -- preserves Weekend Profile's
    /// original "indefinite until stopped" behavior for anyone who never touches this setting.
    static var indefinite: Bool {
        get {
            guard defaults.object(forKey: indefiniteKey) != nil else { return true }
            return defaults.bool(forKey: indefiniteKey)
        }
        set { defaults.set(newValue, forKey: indefiniteKey) }
    }

    /// How long a non-indefinite run should last, when ending by duration rather than by a
    /// specific date/time (see `useSpecificDate`). Captured into `activeEndDate` the moment a run
    /// starts, so changing this later doesn't retroactively change a run already in progress.
    /// Clamped to 0...5760 (4 days); meaningless while `indefinite` is `true` or `useSpecificDate`
    /// is `true`.
    static var durationMinutes: Decimal {
        get { Decimal(defaults.double(forKey: durationMinutesKey)).clamped(to: durationRange) }
        set {
            defaults.set(Double(truncating: newValue.clamped(to: durationRange) as NSNumber), forKey: durationMinutesKey)
        }
    }

    /// When `true` (and `indefinite` is `false`), the run ends at the absolute `scheduledEndDate`
    /// below instead of `durationMinutes` after it started. Defaults to `false` -- duration is the
    /// original non-indefinite option, this is the newer alternative alongside it.
    static var useSpecificDate: Bool {
        get { defaults.bool(forKey: useSpecificDateKey) }
        set { defaults.set(newValue, forKey: useSpecificDateKey) }
    }

    /// The absolute end date/time for a `useSpecificDate` run, e.g. "Sunday 8 PM" rather than "52
    /// hours from now". `nil` until explicitly set. Unlike `durationMinutes`, this doesn't depend
    /// on `activeStartDate` at all -- it's the same moment in wall-clock time no matter when the
    /// run actually starts.
    static var scheduledEndDate: Date? {
        get { defaults.object(forKey: scheduledEndDateKey) as? Date }
        set { defaults.set(newValue, forKey: scheduledEndDateKey) }
    }

    /// The real end time of the current run, or `nil` while inactive or indefinite. A display
    /// value only -- `isExpired` below is what actually gates the algorithm and the auto-stop
    /// check, so this and `isExpired` can never disagree with each other. Falls back to treating
    /// the run as indefinite (returns `nil`) if `useSpecificDate` is somehow `true` with no date
    /// actually recorded, rather than crashing or silently using some other date.
    static var activeEndDate: Date? {
        guard !indefinite, let start = activeStartDate else { return nil }
        if useSpecificDate {
            return scheduledEndDate
        }
        return start.addingTimeInterval(TimeInterval(truncating: durationMinutes as NSNumber) * 60)
    }

    /// True once a non-indefinite run's duration has elapsed. Computed fresh every time it's read
    /// -- nothing here mutates state, so this is safe to call from the dosing algorithm itself
    /// (`OpenAPS.prepareTrioCustomOrefVariables`/`createProfiles`) as well as from
    /// `expireIfNeeded` below.
    static var isExpired: Bool {
        guard let end = activeEndDate else { return false }
        return Date() >= end
    }

    /// One completed Weekend Profile run: an on/off pair with the name it had at the time.
    struct Run: Codable, Identifiable {
        var id = UUID()
        let name: String
        let startDate: Date
        let endDate: Date
    }

    /// Past completed runs, most-recent-last. Lets Trio's own History > Adjustments list show
    /// Weekend Profile the same way it shows Overrides and Temp Targets -- anchored to real
    /// start/end times -- even though Weekend Profile itself has no Core Data record. Capped to the
    /// most recent 200 runs so this doesn't grow unbounded in UserDefaults.
    static var runHistory: [Run] {
        get {
            guard let data = defaults.data(forKey: runHistoryKey),
                  let decoded = try? JSONDecoder().decode([Run].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            let capped = Array(newValue.suffix(200))
            guard let data = try? JSONEncoder().encode(capped) else { return }
            defaults.set(data, forKey: runHistoryKey)
        }
    }

    /// Appends a completed run to `runHistory`. No-ops for a zero/negative-length run (e.g. toggled
    /// on and immediately off) so the history doesn't fill up with noise.
    static func recordCompletedRun(name: String, start: Date, end: Date) {
        guard end > start else { return }
        runHistory.append(Run(name: name, startDate: start, endDate: end))
    }

    /// User-editable label. Defaults to "Profile"; shown in the section header, the Save
    /// button's confirmation, the Nightscout Note marker, and the Home screen indicator.
    static var name: String {
        get {
            let stored = defaults.string(forKey: nameKey) ?? ""
            return stored.isEmpty ? "Profile" : stored
        }
        set { defaults.set(newValue, forKey: nameKey) }
    }

    /// BG target while active, in mg/dL. `0` means "no target override" -- same convention as
    /// `OverrideStored.target`/`overrideTarget`. When non-zero, clamped to 72...270 mg/dL,
    /// matching the range Trio's own Override target picker allows.
    static var target: Decimal {
        get { Decimal(defaults.double(forKey: targetKey)) }
        set {
            let clamped = newValue == 0 ? 0 : newValue.clamped(to: targetRange)
            defaults.set(Double(truncating: clamped as NSNumber), forKey: targetKey)
        }
    }

    /// Max SMB basal minutes while active. Defaults to 30 (Trio's own default) until explicitly
    /// set -- in practice the UI prefills this from the real setting before the first Save, so
    /// this default is only a last-resort fallback. Clamped to 0...180.
    static var smbMinutes: Decimal {
        get {
            guard defaults.object(forKey: smbMinutesKey) != nil else { return 30 }
            return Decimal(defaults.double(forKey: smbMinutesKey))
        }
        set {
            defaults.set(Double(truncating: newValue.clamped(to: minutesRange) as NSNumber), forKey: smbMinutesKey)
        }
    }

    /// Max UAM basal minutes while active. Defaults to 30 (Trio's own default) until explicitly
    /// set -- see `smbMinutes` above re: prefill. Clamped to 0...180.
    static var uamMinutes: Decimal {
        get {
            guard defaults.object(forKey: uamMinutesKey) != nil else { return 30 }
            return Decimal(defaults.double(forKey: uamMinutesKey))
        }
        set {
            defaults.set(Double(truncating: newValue.clamped(to: minutesRange) as NSNumber), forKey: uamMinutesKey)
        }
    }

    /// Weekend's own full time-of-day basal schedule -- same shape as the real Basal Profile
    /// Editor's `[BasalProfileEntry]`. Empty until the editor is saved for the first time.
    static var basalProfile: [BasalProfileEntry] {
        get {
            guard let data = defaults.data(forKey: basalProfileKey),
                  let decoded = try? JSONDecoder().decode([BasalProfileEntry].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: basalProfileKey)
        }
    }

    /// Weekend's own full time-of-day ISF schedule -- same shape as the real ISF Editor's
    /// `InsulinSensitivities`. `nil`/empty until the editor is saved for the first time.
    static var insulinSensitivities: InsulinSensitivities? {
        get {
            guard let data = defaults.data(forKey: insulinSensitivitiesKey),
                  let decoded = try? JSONDecoder().decode(InsulinSensitivities.self, from: data)
            else { return nil }
            return decoded
        }
        set {
            guard let newValue else {
                defaults.removeObject(forKey: insulinSensitivitiesKey)
                return
            }
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: insulinSensitivitiesKey)
        }
    }
}

// MARK: - Shared start/stop sequence

extension WeekendProfileStore {
    /// ~30 days, in minutes -- Trio's convention for representing an indefinite-duration entry
    /// (see `OverrideStorage.getOverrideRunsNotYetUploadedToNightscout`). `activate` posts a
    /// Nightscout entry with this duration; `deactivate` corrects it to the real elapsed time.
    static let indefiniteDurationMinutes = 43200

    /// Distinguishes a Weekend Profile run from a real Override on Nightscout even though both
    /// share the "Exercise" eventType and Trio's usual `enteredBy` of "Trio".
    static let enteredBy = "Trio Weekend Profile"

    /// Turns Weekend Profile on: flips `isActive`, records the real start time (so the run can be
    /// anchored in History > Adjustments and its real duration computed once stopped), and posts an
    /// indefinite-duration "Exercise" entry to Nightscout so Loop Follow (and any Nightscout-based
    /// viewer that already understands Trio Overrides) picks it up automatically. No-ops if already
    /// active.
    ///
    /// This is the combined sequence used by the Trio Remote Control command handler
    /// (`TrioRemoteControl+WeekendProfile.swift`), which has no SwiftUI view to drive it. The in-app
    /// toggle in `WeekendProfileSection` performs the same steps itself -- setting `isActive`
    /// directly from its `Toggle` binding, then calling `Adjustments.StateModel.startWeekendProfile()`
    /// for the timing/Nightscout side effects -- rather than going through this helper, but both
    /// paths leave Weekend Profile in the identical state.
    static func activate(nightscoutManager: NightscoutManager) {
        guard !isActive else { return }
        isActive = true
        let start = Date()
        activeStartDate = start
        Task {
            let event = NightscoutExercise(
                duration: indefiniteDurationMinutes,
                eventType: .nsExercise,
                createdAt: start,
                enteredBy: enteredBy,
                notes: name
            )
            await nightscoutManager.uploadWeekendProfileEvent(event, replacingPrevious: false)
        }
    }

    /// Turns Weekend Profile off: flips `isActive`, records the completed run (so it's anchored in
    /// History > Adjustments with its real start/end), and corrects the Nightscout entry `activate`
    /// posted from its indefinite duration to the real elapsed one. No-ops if already inactive, or if
    /// there's no recorded start time to close out (e.g. Weekend Profile was active before this
    /// version's start-tracking existed) -- see the counterpart in `Adjustments.StateModel
    /// .stopWeekendProfile()` for the same guard.
    static func deactivate(nightscoutManager: NightscoutManager) {
        guard isActive else { return }
        isActive = false
        let end = Date()
        let runName = name
        guard let start = activeStartDate else { return }
        activeStartDate = nil
        recordCompletedRun(name: runName, start: start, end: end)

        let elapsedMinutes = max(1, Int(end.timeIntervalSince(start) / 60))
        Task {
            let event = NightscoutExercise(
                duration: elapsedMinutes,
                eventType: .nsExercise,
                createdAt: start,
                enteredBy: enteredBy,
                notes: runName
            )
            await nightscoutManager.uploadWeekendProfileEvent(event, replacingPrevious: true)
        }
    }

    /// Closes out a run whose duration has elapsed: identical bookkeeping to a manual stop
    /// (Nightscout correction, run history, flipping `isActive` off). Meant to be called
    /// periodically from somewhere that already runs on roughly every loop cycle (see
    /// `Home.StateModel.updateEnactedDeterminationFromController`), so an expired run gets closed
    /// out and reflected in the UI at about the same cadence the algorithm stops honoring it at.
    /// That said, dosing safety never depends on this actually being called: `isExpired` is
    /// checked directly and independently inside `OpenAPS.swift`, so even if this were never
    /// invoked, an expired Weekend Profile would still stop affecting insulin dosing on the very
    /// next loop cycle -- this only controls how promptly the on/off state, Nightscout entry, and
    /// History list catch up to that fact. Returns whether anything was actually stopped, so
    /// callers can decide whether to refresh UI/post a notification.
    @discardableResult
    static func expireIfNeeded(nightscoutManager: NightscoutManager) -> Bool {
        guard isExpired else { return false }
        deactivate(nightscoutManager: nightscoutManager)
        return true
    }
}

private extension Decimal {
    func clamped(to range: ClosedRange<Decimal>) -> Decimal {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
