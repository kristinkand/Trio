import Foundation
import Testing
@testable import Trio

/// The profile (Adjustments › Profile): when a run ends, when the loop takes it, what it doses from, and what its
/// History and Nightscout entries get, on the phone and on the untethered watch.
@Suite("Profile") struct ProfileRulesTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func minutes(_ m: Double) -> TimeInterval { m * 60 }

    let regularBasal = [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)]
    let profileBasal = [
        BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0.5),
        BasalProfileEntry(start: "06:00:00", minutes: 360, rate: 0.75)
    ]
    let regularISF = InsulinSensitivities(
        units: .mgdL,
        userPreferredUnits: .mgdL,
        sensitivities: [InsulinSensitivityEntry(sensitivity: 50, offset: 0, start: "00:00:00")]
    )
    let profileISF = InsulinSensitivities(
        units: .mgdL,
        userPreferredUnits: .mgdL,
        sensitivities: [InsulinSensitivityEntry(sensitivity: 70, offset: 0, start: "00:00:00")]
    )

    // MARK: - When a run ends

    @Test("A run until stopped has no end") func indefiniteHasNoEnd() {
        let end = ProfileRules.endDate(
            start: t0,
            indefinite: true,
            useSpecificDate: false,
            durationMinutes: 90,
            scheduledEndDate: t0.addingTimeInterval(minutes(30))
        )
        #expect(end == nil)
    }

    @Test("A profile that isn't running has no end") func notRunningHasNoEnd() {
        let end = ProfileRules.endDate(
            start: nil,
            indefinite: false,
            useSpecificDate: false,
            durationMinutes: 90,
            scheduledEndDate: nil
        )
        #expect(end == nil)
    }

    @Test("A run by duration ends that many minutes after its start") func durationEnd() {
        let end = ProfileRules.endDate(
            start: t0,
            indefinite: false,
            useSpecificDate: false,
            durationMinutes: 90,
            scheduledEndDate: t0.addingTimeInterval(minutes(30))
        )
        #expect(end == t0.addingTimeInterval(minutes(90)))
    }

    @Test("A run by date & time ends at that date, whenever it started") func specificDateEnd() {
        let date = t0.addingTimeInterval(minutes(52 * 60))
        for start in [t0, t0.addingTimeInterval(minutes(600))] {
            let end = ProfileRules.endDate(
                start: start,
                indefinite: false,
                useSpecificDate: true,
                durationMinutes: 90,
                scheduledEndDate: date
            )
            #expect(end == date)
        }
    }

    @Test("A run by date & time without a date runs until stopped") func specificDateMissing() {
        let end = ProfileRules.endDate(
            start: t0,
            indefinite: false,
            useSpecificDate: true,
            durationMinutes: 90,
            scheduledEndDate: nil
        )
        #expect(end == nil)
    }

    @Test("A run has ended from its end time on") func expiry() {
        let end = t0.addingTimeInterval(minutes(60))
        #expect(!ProfileRules.isExpired(endDate: end, now: end.addingTimeInterval(-1)))
        #expect(ProfileRules.isExpired(endDate: end, now: end))
        #expect(ProfileRules.isExpired(endDate: end, now: end.addingTimeInterval(1)))
        #expect(!ProfileRules.isExpired(endDate: nil, now: .distantFuture))
    }

    // MARK: - When the loop takes it

    @Test("The loop takes it only while it runs and no override or temp target runs") func applies() {
        #expect(ProfileRules.applies(isActive: true, isExpired: false, overrideActive: false, tempTargetActive: false))
        #expect(!ProfileRules.applies(isActive: false, isExpired: false, overrideActive: false, tempTargetActive: false))
        #expect(!ProfileRules.applies(isActive: true, isExpired: true, overrideActive: false, tempTargetActive: false))
        #expect(!ProfileRules.applies(isActive: true, isExpired: false, overrideActive: true, tempTargetActive: false))
        #expect(!ProfileRules.applies(isActive: true, isExpired: false, overrideActive: false, tempTargetActive: true))
    }

    // MARK: - What the loop doses from

    @Test("Its basal and ISF schedules replace the regular ones") func schedulesReplaced() {
        let s = ProfileRules.schedules(
            regularBasal: regularBasal,
            regularSensitivities: regularISF,
            profileBasal: profileBasal,
            profileSensitivities: profileISF
        )
        #expect(s.basal == profileBasal)
        #expect(s.sensitivities == profileISF)
    }

    @Test("A schedule it doesn't have keeps the regular one") func emptySchedulesKeepRegular() {
        let noBasal = ProfileRules.schedules(
            regularBasal: regularBasal,
            regularSensitivities: regularISF,
            profileBasal: [],
            profileSensitivities: profileISF
        )
        #expect(noBasal.basal == regularBasal)
        #expect(noBasal.sensitivities == profileISF)

        let noISF = ProfileRules.schedules(
            regularBasal: regularBasal,
            regularSensitivities: regularISF,
            profileBasal: profileBasal,
            profileSensitivities: nil
        )
        #expect(noISF.basal == profileBasal)
        #expect(noISF.sensitivities == regularISF)

        let emptyISF = InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: [])
        let emptied = ProfileRules.schedules(
            regularBasal: regularBasal,
            regularSensitivities: regularISF,
            profileBasal: profileBasal,
            profileSensitivities: emptyISF
        )
        #expect(emptied.sensitivities == regularISF)
    }

    @Test("oref gets it as an override at 100 % with its target and SMB/UAM minutes") func orefOverride() {
        let override = ProfileRules.override(target: 110, smbMinutes: 45, uamMinutes: 60, now: t0)
        #expect(override.enabled)
        #expect(override.indefinite)
        #expect(override.percentage == 100)
        #expect(!override.isf && !override.cr && !override.isfAndCr)
        #expect(!override.smbIsOff && !override.smbIsScheduledOff)

        let variables = OrefPipeline.customOrefVariables(
            override: override,
            tdd: OrefPipeline.TDDSummary(currentTDD: 40, averageLastTenDays: 38, averageLastTwoHours: 2),
            preferences: Preferences(),
            now: t0
        )
        #expect(variables.useOverride)
        #expect(variables.overridePercentage == 100)
        #expect(variables.overrideTarget == 110)
        #expect(variables.smbMinutes == 45)
        #expect(variables.uamMinutes == 60)
        #expect(!variables.isf && !variables.cr && !variables.isfAndCr)
    }

    @Test("Without a target of its own, oref keeps the regular target") func noTarget() {
        let variables = OrefPipeline.customOrefVariables(
            override: ProfileRules.override(target: 0, smbMinutes: 30, uamMinutes: 30, now: t0),
            tdd: OrefPipeline.TDDSummary(currentTDD: 40, averageLastTenDays: 38, averageLastTwoHours: 2),
            preferences: Preferences(),
            now: t0
        )
        #expect(variables.overrideTarget == 0)
    }

    // MARK: - History and Nightscout

    @Test("Nightscout gets the planned length at the start, about 30 days until stopped") func nightscoutStart() {
        #expect(ProfileRules.nightscoutStartMinutes(start: t0, endDate: nil) == 43200)
        #expect(ProfileRules.nightscoutStartMinutes(start: t0, endDate: t0.addingTimeInterval(minutes(90))) == 90)
        // part of a minute counts as one, so LoopFollow never shows it ending early
        #expect(ProfileRules.nightscoutStartMinutes(start: t0, endDate: t0.addingTimeInterval(minutes(90.5))) == 91)
        #expect(ProfileRules.nightscoutStartMinutes(start: t0, endDate: t0.addingTimeInterval(-60)) == 1)
    }

    @Test("A run that ended before it was stopped ended at its end time") func stopDate() {
        let end = t0.addingTimeInterval(minutes(60))
        let earlier = t0.addingTimeInterval(minutes(30))
        let later = t0.addingTimeInterval(minutes(89))
        #expect(ProfileRules.stopDate(requested: earlier, endDate: end) == earlier)
        #expect(ProfileRules.stopDate(requested: later, endDate: end) == end)
        #expect(ProfileRules.stopDate(requested: later, endDate: nil) == later)
    }

    @Test("The Nightscout correction counts whole minutes, at least 1") func elapsed() {
        #expect(ProfileRules.elapsedMinutes(start: t0, end: t0.addingTimeInterval(59)) == 1)
        #expect(ProfileRules.elapsedMinutes(start: t0, end: t0.addingTimeInterval(minutes(125.5))) == 125)
        #expect(ProfileRules.elapsedMinutes(start: t0, end: t0) == 1)
    }

    @Test("Only a run with a length goes into History") func recordable() {
        #expect(!ProfileRules.isRecordable(start: t0, end: t0))
        #expect(!ProfileRules.isRecordable(start: t0, end: t0.addingTimeInterval(-1)))
        #expect(ProfileRules.isRecordable(start: t0, end: t0.addingTimeInterval(1)))
    }

    @Test("History keeps the newest 200 runs") func historyCap() {
        let capped = ProfileRules.cappedHistory(Array(1 ... 250))
        #expect(capped.count == 200)
        #expect(capped.first == 51)
        #expect(capped.last == 250)
        #expect(ProfileRules.cappedHistory([1, 2, 3]) == [1, 2, 3])
    }

    // MARK: - Stored values

    @Test("Target, minutes and duration stay within their ranges") func clamps() {
        #expect(ProfileRules.clampedTarget(0) == 0)
        #expect(ProfileRules.clampedTarget(50) == 72)
        #expect(ProfileRules.clampedTarget(100) == 100)
        #expect(ProfileRules.clampedTarget(300) == 270)
        #expect(ProfileRules.clampedMinutes(-5) == 0)
        #expect(ProfileRules.clampedMinutes(45) == 45)
        #expect(ProfileRules.clampedMinutes(200) == 180)
        #expect(ProfileRules.clampedDuration(-1) == 0)
        #expect(ProfileRules.clampedDuration(6000) == 5760)
    }

    // MARK: - On the untethered watch

    func watchProfile(endsAt: Date?, basal: [BasalProfileEntry]? = nil) -> UntetheredProfile {
        UntetheredProfile(
            name: "Weekend",
            override: ProfileRules.override(target: 110, smbMinutes: 45, uamMinutes: 60, now: t0),
            basalProfile: basal ?? profileBasal,
            insulinSensitivities: profileISF,
            endsAt: endsAt,
            startedAt: t0
        )
    }

    @Test("The watch counts a run as ended at the same moment as the phone") func watchEndsWithPhone() {
        let end = t0.addingTimeInterval(minutes(60))
        let profile = watchProfile(endsAt: end)
        for now in [end.addingTimeInterval(-1), end, end.addingTimeInterval(1)] {
            #expect(profile.isRunning(at: now) == !ProfileRules.isExpired(endDate: end, now: now))
        }
        #expect(watchProfile(endsAt: nil).isRunning(at: .distantFuture))
    }

    @Test("The watch loops on the profile's basal and ISF, keeping its carb ratios") func watchLoopsOnProfile() {
        var grant = UntetheredTests().grant()
        grant.profile = watchProfile(endsAt: t0.addingTimeInterval(minutes(60)))
        let taken = grant.withProfile(at: t0, overrideOrTempTargetActive: false)
        #expect(taken.basalProfile == profileBasal)
        #expect(taken.insulinSensitivities == profileISF)
        #expect(taken.carbRatios == grant.carbRatios)

        // the phone's loop doses from the same schedules
        let phone = ProfileRules.schedules(
            regularBasal: grant.basalProfile,
            regularSensitivities: grant.insulinSensitivities,
            profileBasal: profileBasal,
            profileSensitivities: profileISF
        )
        #expect(taken.basalProfile == phone.basal)
        #expect(taken.insulinSensitivities == phone.sensitivities)
    }

    @Test("The watch keeps its regular schedules under an override or temp target, or after the end") func watchRegular() {
        var grant = UntetheredTests().grant()
        let end = t0.addingTimeInterval(minutes(60))
        grant.profile = watchProfile(endsAt: end)

        let underOverride = grant.withProfile(at: t0, overrideOrTempTargetActive: true)
        #expect(underOverride.basalProfile == grant.basalProfile)
        #expect(underOverride.insulinSensitivities == grant.insulinSensitivities)

        let afterEnd = grant.withProfile(at: end, overrideOrTempTargetActive: false)
        #expect(afterEnd.basalProfile == grant.basalProfile)
        #expect(afterEnd.insulinSensitivities == grant.insulinSensitivities)

        grant.profile = nil
        let none = grant.withProfile(at: t0, overrideOrTempTargetActive: false)
        #expect(none.basalProfile == grant.basalProfile)
    }

    @Test("A profile without a basal schedule keeps the watch's regular basal") func watchEmptyBasal() {
        var grant = UntetheredTests().grant()
        grant.profile = watchProfile(endsAt: nil, basal: [])
        let taken = grant.withProfile(at: t0, overrideOrTempTargetActive: false)
        #expect(taken.basalProfile == grant.basalProfile)
        #expect(taken.insulinSensitivities == profileISF)
    }

    @Test("A profile from a phone build without its start time still reaches the watch") func watchOlderPhone() throws {
        let data = try JSONEncoder().encode(watchProfile(endsAt: t0.addingTimeInterval(minutes(60))))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "startedAt")
        let older = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(UntetheredProfile.self, from: older)
        #expect(decoded.startedAt == nil)
        #expect(decoded.name == "Weekend")
        #expect(decoded.basalProfile == profileBasal)
    }
}
