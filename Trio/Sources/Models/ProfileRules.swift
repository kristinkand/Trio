import Foundation

/// The rules of the profile (Adjustments › Profile) as plain functions of their inputs: when a run ends, whether the
/// loop takes it, what it hands to oref, and the numbers its History and Nightscout entries get. `WeekendProfileStore`,
/// `OpenAPS` and the untethered watch all go through these, so `ProfileRulesTests` checks the code the app runs.
enum ProfileRules {
    /// Its target in mg/dL when set (0 is none), as Trio's override target picker allows.
    static let targetRange: ClosedRange<Decimal> = 72 ... 270
    /// SMB and UAM minutes.
    static let minutesRange: ClosedRange<Decimal> = 0 ... 180
    /// A run by duration lasts up to 4 days.
    static let durationRange: ClosedRange<Decimal> = 0 ... 5760
    /// About 30 days: what Nightscout gets for a run until stopped, as Trio sends an indefinite override.
    static let indefiniteNightscoutMinutes = 43200
    /// The completed runs kept for History.
    static let historyLimit = 200

    // MARK: - When it runs

    /// When a run ends: nil while it isn't running (no start) or runs until stopped. A run by date & time ends at that
    /// date (nil when none was set: until stopped), a run by duration that many minutes after its start.
    static func endDate(
        start: Date?,
        indefinite: Bool,
        useSpecificDate: Bool,
        durationMinutes: Decimal,
        scheduledEndDate: Date?
    ) -> Date? {
        guard !indefinite, let start else { return nil }
        if useSpecificDate {
            return scheduledEndDate
        }
        return start.addingTimeInterval(TimeInterval(truncating: durationMinutes as NSNumber) * 60)
    }

    /// From its end on; never for a run until stopped.
    static func isExpired(endDate: Date?, now: Date) -> Bool {
        guard let endDate else { return false }
        return now >= endDate
    }

    /// Whether the loop takes the profile: while it runs and has not ended, and neither an override nor a temp target
    /// runs (they take over, and it comes back when they end).
    static func applies(isActive: Bool, isExpired: Bool, overrideActive: Bool, tempTargetActive: Bool) -> Bool {
        isActive && !isExpired && !overrideActive && !tempTargetActive
    }

    // MARK: - What the loop gets

    /// The schedules the loop doses from while the profile applies: its own basal and ISF in place of the regular
    /// ones, each only when it has entries (one never saved keeps the regular). Carb ratios are never touched.
    static func schedules(
        regularBasal: [BasalProfileEntry],
        regularSensitivities: InsulinSensitivities,
        profileBasal: [BasalProfileEntry],
        profileSensitivities: InsulinSensitivities?
    ) -> (basal: [BasalProfileEntry], sensitivities: InsulinSensitivities) {
        let basal = profileBasal.isEmpty ? regularBasal : profileBasal
        let sensitivities: InsulinSensitivities
        if let profileSensitivities, !profileSensitivities.sensitivities.isEmpty {
            sensitivities = profileSensitivities
        } else {
            sensitivities = regularSensitivities
        }
        return (basal, sensitivities)
    }

    /// The profile as oref reads it: an override at 100 % until stopped, with the profile's target (0: the regular
    /// one) and SMB/UAM minutes, never changing ISF or carb ratio.
    static func override(target: Decimal, smbMinutes: Decimal, uamMinutes: Decimal, now: Date) -> Override {
        Override(
            name: "Weekend Profile",
            enabled: true,
            date: now,
            duration: 0,
            indefinite: true,
            percentage: 100,
            smbIsOff: false,
            isPreset: false,
            id: "",
            overrideTarget: true,
            target: target,
            advancedSettings: true,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: smbMinutes,
            uamMinutes: uamMinutes
        )
    }

    // MARK: - History and Nightscout

    /// The minutes Nightscout gets when a run starts: its planned length when it has an end, so LoopFollow shows the
    /// right end even if the correction at the stop never gets through; about 30 days for a run until stopped.
    static func nightscoutStartMinutes(start: Date, endDate: Date?) -> Int {
        guard let endDate else { return indefiniteNightscoutMinutes }
        return max(1, Int((endDate.timeIntervalSince(start) / 60).rounded(.up)))
    }

    /// When a run stopped: the stop, or its end when that came first (a run that ended while Trio wasn't running
    /// ended at its end time, not when Trio next looked).
    static func stopDate(requested: Date, endDate: Date?) -> Date {
        min(requested, endDate ?? .distantFuture)
    }

    /// The minutes Nightscout's entry is corrected to at the stop: whole minutes run, at least 1.
    static func elapsedMinutes(start: Date, end: Date) -> Int {
        max(1, Int(end.timeIntervalSince(start) / 60))
    }

    /// Only a run with a length goes into History (not one turned on and straight off).
    static func isRecordable(start: Date, end: Date) -> Bool {
        end > start
    }

    /// The newest `historyLimit` runs.
    static func cappedHistory<Run>(_ runs: [Run]) -> [Run] {
        Array(runs.suffix(historyLimit))
    }

    // MARK: - Stored values

    /// 0 stays 0 (no target of its own); anything else within `targetRange`.
    static func clampedTarget(_ target: Decimal) -> Decimal {
        target == 0 ? 0 : clamp(target, to: targetRange)
    }

    static func clampedMinutes(_ minutes: Decimal) -> Decimal {
        clamp(minutes, to: minutesRange)
    }

    static func clampedDuration(_ minutes: Decimal) -> Decimal {
        clamp(minutes, to: durationRange)
    }

    private static func clamp(_ value: Decimal, to range: ClosedRange<Decimal>) -> Decimal {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
