import Foundation
import Observation

/// What the iPhone last told the watch about itself: when it was last heard from, its newest own reading and dose,
/// the units and its glucose alarm thresholds. Kept, so the watch carries on alone. Untethered mode and the screens
/// read it here, whichever reader has the sensor; the stored keys are the watch reader's from before.
@Observable final class WatchPhoneSigns {
    static let shared = WatchPhoneSigns()

    /// When the last watch state update from the phone was made.
    private(set) var lastPhoneContact: Date?
    /// The newest glucose the phone has. The phone can still reach the watch
    /// while it has lost the sensor (flight mode keeps the watch link), so
    /// this, not the contact, says whether the phone's glucose is current.
    private(set) var phoneGlucoseDate: Date?
    /// When the phone last enacted a temp basal or bolus, from its state. Nil from a phone build without it.
    private(set) var phoneDoseDate: Date?
    private(set) var units: String
    private(set) var urgentLowMgDL: Double
    private(set) var lowMgDL: Double?
    private(set) var highMgDL: Double?

    private let defaults = UserDefaults.standard

    private enum Key {
        static let units = "watchG7.units"
        static let urgentLow = "watchG7.urgentLowMgDL"
        static let low = "watchG7.lowMgDL"
        static let high = "watchG7.highMgDL"
        static let lastPhoneContact = "watchG7.lastPhoneContact"
        static let phoneGlucoseDate = "watchG7.phoneGlucoseDate"
        static let phoneDoseDate = "watchG7.phoneDoseDate"
    }

    private init() {
        units = defaults.string(forKey: Key.units) ?? "mg/dL"
        urgentLowMgDL = defaults.object(forKey: Key.urgentLow) as? Double ?? 54
        lowMgDL = defaults.object(forKey: Key.low) as? Double
        highMgDL = defaults.object(forKey: Key.high) as? Double
        lastPhoneContact = defaults.object(forKey: Key.lastPhoneContact) as? Date
        phoneGlucoseDate = defaults.object(forKey: Key.phoneGlucoseDate) as? Date
        phoneDoseDate = defaults.object(forKey: Key.phoneDoseDate) as? Date
    }

    /// The newest sign that the phone loops: its own newest reading or its last dose, whichever is newer. Contact
    /// alone isn't one (22 October: a phone in a metal pot got through for 5 s with only an old reading), nor are its
    /// status reads of the pod (8 November: a phone without a sensor kept reaching the pod and couldn't loop).
    var phoneLoopSign: Date? {
        [phoneGlucoseDate, phoneDoseDate].compactMap { $0 }.max()
    }

    /// The phone took the pump back from an untethered session: it doses from now on, as its next state will say,
    /// often minutes late (11 November, 10:51: the fallback looked at the pod 5 minutes after a hand-back, and the
    /// look cost the phone its next loop). Counts as its newest dose until the state brings a newer one.
    func notePhoneTookPump(at date: Date = Date()) {
        guard date > (phoneDoseDate ?? .distantPast) else { return }
        phoneDoseDate = date
        defaults.set(date, forKey: Key.phoneDoseDate)
    }

    /// The phone's own newest reading as its wake carries it (`untetheredWake`), ahead of the state that brings it
    /// too: the hand-back to a phone that reads again goes by this date.
    func notePhoneOwnReading(_ date: Date) {
        guard date > (phoneGlucoseDate ?? .distantPast) else { return }
        phoneGlucoseDate = date
        defaults.set(date, forKey: Key.phoneGlucoseDate)
    }

    var isMmol: Bool { units == "mmol/L" }

    func format(_ mgdl: Double) -> String {
        isMmol ? String(format: "%.1f", mgdl * 0.0555) : String(Int(mgdl.rounded()))
    }

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

    /// Takes in a phone state. Returns the phone's newest own reading when the state carries readings.
    @discardableResult func update(from payload: [String: Any]) -> Date? {
        if let timestamp = payload[WatchMessageKeys.date] as? TimeInterval {
            let date = Date(timeIntervalSince1970: timestamp)
            if date > (lastPhoneContact ?? .distantPast) {
                lastPhoneContact = date
                defaults.set(date, forKey: Key.lastPhoneContact)
            }
        }

        var phoneReading: Date?
        if let values = payload[WatchMessageKeys.glucoseValues] as? [[String: Any]],
           let newest = values.compactMap({ $0["date"] as? TimeInterval }).max()
        {
            var date = Date(timeIntervalSince1970: newest)
            // The phone's state also carries the watch's own readings it stored: what counts is when the phone itself
            // last read one (30 October: its Bluetooth off, it kept sending the watch's readings back, and the watch
            // took that for the phone being back). A phone build without the key is taken as before.
            if let own = payload[WatchMessageKeys.phoneOwnGlucoseDate] as? TimeInterval {
                date = min(date, Date(timeIntervalSince1970: own))
            }
            phoneGlucoseDate = date
            defaults.set(date, forKey: Key.phoneGlucoseDate)
            phoneReading = date
        }
        if let dose = payload[WatchMessageKeys.phoneLastDoseDate] as? TimeInterval {
            let date = Date(timeIntervalSince1970: dose)
            if date > (phoneDoseDate ?? .distantPast) {
                phoneDoseDate = date
                defaults.set(date, forKey: Key.phoneDoseDate)
            }
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
        return phoneReading
    }
}
