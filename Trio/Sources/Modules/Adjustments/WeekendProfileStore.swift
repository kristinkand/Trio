import Foundation

/// A manual, indefinite-until-stopped "second profile" toggle, independent of Trio's Overrides
/// system. Turning it on swaps in its own full time-of-day BASAL and ISF schedules (the exact
/// same `[BasalProfileEntry]` / `InsulinSensitivities` types the real Basal Profile Editor / ISF
/// Editor use), plus an optional BG target and SMB/UAM minutes -- via `OpenAPS.createProfiles()`
/// (basal/ISF) and `OpenAPS.prepareTrioCustomOrefVariables` (target/SMB/UAM minutes). Carb ratio
/// is deliberately never touched here -- there is no `carbRatios` field at all, so CR always comes
/// from the normal settings.
///
/// Unlike an Override:
///   - It isn't time-limited -- meant for stretches you start and stop yourself (a weekend, a
///     vacation), not just a single loop cycle's duration.
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
    private static let nameKey = "weekendProfileName"
    private static let targetKey = "weekendProfileTarget"
    private static let smbMinutesKey = "weekendProfileSMBMinutes"
    private static let uamMinutesKey = "weekendProfileUAMMinutes"
    private static let basalProfileKey = "weekendProfileBasalProfileData"
    private static let insulinSensitivitiesKey = "weekendProfileInsulinSensitivitiesData"

    private static let targetRange: ClosedRange<Decimal> = 72 ... 270
    private static let minutesRange: ClosedRange<Decimal> = 0 ... 180

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

    /// User-editable label. Defaults to "Weekend Profile"; shown in the section header, the Save
    /// button's confirmation, the Nightscout Note marker, and the Home screen indicator.
    static var name: String {
        get {
            let stored = defaults.string(forKey: nameKey) ?? ""
            return stored.isEmpty ? "Weekend Profile" : stored
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

private extension Decimal {
    func clamped(to range: ClosedRange<Decimal>) -> Decimal {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
