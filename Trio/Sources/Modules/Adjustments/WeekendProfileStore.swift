import Foundation

/// A manual, indefinite-until-stopped "second profile" toggle, independent of Trio's Overrides
/// system. Turning it on applies a percentage (to basal/ISF/CR together, same meaning as
/// `OverrideStored.percentage`), an optional BG target, and SMB/UAM minutes -- via the exact
/// same algorithm machinery a real Override uses (see `OpenAPS.prepareTrioCustomOrefVariables`).
///
/// Unlike an Override:
///   - It isn't time-limited -- meant for stretches you start and stop yourself (a weekend, a
///     vacation), not just a single loop cycle's duration.
///   - It never blocks a real Override from running. Whenever a real Override is active, that
///     Override fully takes over the dosing math and Weekend Profile is ignored, automatically
///     resuming the moment the Override ends -- so e.g. a low-glucose-recovery Override still
///     works exactly as it always has, any time, regardless of whether Weekend Profile is on.
///
/// Backed by UserDefaults (not Core Data) since it's a single global on/off setting with no
/// history, presets, or Nightscout sync to manage -- same pattern as the Food Impact override
/// stores in `MealImpactSetup.swift`. Values are clamped to the same safe ranges Trio's own
/// Override editor uses, as defense in depth beyond whatever UI writes them.
enum WeekendProfileStore {
    private static let isActiveKey = "weekendProfileIsActive"
    private static let percentageKey = "weekendProfilePercentage"
    private static let targetKey = "weekendProfileTarget"
    private static let smbMinutesKey = "weekendProfileSMBMinutes"
    private static let uamMinutesKey = "weekendProfileUAMMinutes"

    private static let percentageRange: ClosedRange<Decimal> = 40 ... 150
    private static let targetRange: ClosedRange<Decimal> = 72 ... 270
    private static let minutesRange: ClosedRange<Decimal> = 0 ... 180

    /// Whether Weekend Profile is currently on. Defaults to `false`.
    static var isActive: Bool {
        get { UserDefaults.standard.bool(forKey: isActiveKey) }
        set { UserDefaults.standard.set(newValue, forKey: isActiveKey) }
    }

    /// Percentage applied to basal, ISF, and carb ratio together while active. Defaults to 100
    /// (no change) until explicitly set. Clamped to 40...150, matching the range Trio's own
    /// Override percentage picker allows.
    static var percentage: Decimal {
        get {
            guard UserDefaults.standard.object(forKey: percentageKey) != nil else { return 100 }
            return Decimal(UserDefaults.standard.double(forKey: percentageKey))
        }
        set {
            UserDefaults.standard.set(
                Double(truncating: newValue.clamped(to: percentageRange) as NSNumber),
                forKey: percentageKey
            )
        }
    }

    /// BG target while active, in mg/dL. `0` means "no target override" -- same convention as
    /// `OverrideStored.target`/`overrideTarget`. When non-zero, clamped to 72...270 mg/dL,
    /// matching the range Trio's own Override target picker allows.
    static var target: Decimal {
        get { Decimal(UserDefaults.standard.double(forKey: targetKey)) }
        set {
            let clamped = newValue == 0 ? 0 : newValue.clamped(to: targetRange)
            UserDefaults.standard.set(Double(truncating: clamped as NSNumber), forKey: targetKey)
        }
    }

    /// Max SMB basal minutes while active. Defaults to 30 (Trio's own default) until explicitly
    /// set. Clamped to 0...180.
    static var smbMinutes: Decimal {
        get {
            guard UserDefaults.standard.object(forKey: smbMinutesKey) != nil else { return 30 }
            return Decimal(UserDefaults.standard.double(forKey: smbMinutesKey))
        }
        set {
            UserDefaults.standard.set(
                Double(truncating: newValue.clamped(to: minutesRange) as NSNumber),
                forKey: smbMinutesKey
            )
        }
    }

    /// Max UAM basal minutes while active. Defaults to 30 (Trio's own default) until explicitly
    /// set. Clamped to 0...180.
    static var uamMinutes: Decimal {
        get {
            guard UserDefaults.standard.object(forKey: uamMinutesKey) != nil else { return 30 }
            return Decimal(UserDefaults.standard.double(forKey: uamMinutesKey))
        }
        set {
            UserDefaults.standard.set(
                Double(truncating: newValue.clamped(to: minutesRange) as NSNumber),
                forKey: uamMinutesKey
            )
        }
    }
}

private extension Decimal {
    func clamped(to range: ClosedRange<Decimal>) -> Decimal {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
