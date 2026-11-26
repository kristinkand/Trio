import CoreData
import Foundation
import LoopKit
import UserNotifications

/// A small bolus once a new pod runs, to fill what the cannula's first hours take up (Settings › Devices › Insulin Pump ›
/// After a Pod Change). Off unless switched on; once on, it is given after every pod change until switched off. Not
/// given below 5.0 mmol/L (90 mg/dL), nor without a CGM reading from the last 15 minutes: a notification says so.
enum PodChangeBolus {
    static let lowestGlucose = 90
    static let readingMaxAge: TimeInterval = 15 * 60
    /// A pod activated longer ago than this isn't a fresh pod change (Trio launched on an old pod).
    static let podMaxAge: TimeInterval = 2 * 60 * 60

    private static let handledKey = "Trio.podChangeBolus.handledPod"
    private static let enabledAtKey = "Trio.podChangeBolus.enabledAt"
    private static let queue = DispatchQueue(label: "Trio.podChangeBolus")

    /// Switched on: only pods activated from then on get the bolus, not the one already running. Kept while it stays on
    /// (the settings screen reports the setting each time it opens, also during a pod change).
    static func noteEnabled(_ enabled: Bool) {
        if enabled {
            guard UserDefaults.standard.object(forKey: enabledAtKey) == nil else { return }
            UserDefaults.standard.set(Date(), forKey: enabledAtKey)
        } else {
            UserDefaults.standard.removeObject(forKey: enabledAtKey)
        }
    }

    /// Called on each Omnipod status update. Gives the bolus once per pod, once its setup is complete and no bolus runs.
    static func check(
        activatedAt: Date,
        status: PumpManagerStatus,
        enabled: Bool,
        units: Decimal,
        apsManager: APSManager?
    ) {
        guard enabled, let apsManager else { return }
        // on without the switch (a settings import): from now on, as if switched on now
        noteEnabled(true)
        let enabledAt = UserDefaults.standard.object(forKey: enabledAtKey) as? Date ?? .distantFuture
        let handled = UserDefaults.standard.object(forKey: handledKey) as? Date
        guard handled != activatedAt, activatedAt > enabledAt,
              Date().timeIntervalSince(activatedAt) < podMaxAge
        else { return }
        // OmnipodKit reports a pod whose setup isn't complete as active since the distant past
        switch status.basalDeliveryState {
        case let .active(since) where since > .distantPast: break
        case .tempBasal: break
        default: return
        }
        guard case .noBolus = status.bolusState else { return }
        queue.sync {
            guard UserDefaults.standard.object(forKey: handledKey) as? Date != activatedAt else { return }
            // marked first: never twice for one pod, also if the app ends during the bolus
            UserDefaults.standard.set(activatedAt, forKey: handledKey)
            Task { await give(units: units, apsManager: apsManager) }
        }
    }

    private static func give(units: Decimal, apsManager: APSManager) async {
        let amount = units.formatted(.number.precision(.fractionLength(0 ... 2)))
        guard UntetheredGate.phoneMayDose else {
            warning(.bolus, "Pod change bolus of \(amount) U skipped: the watch has the pump")
            notify(String(localized: "No Bolus After the Pod Change"), String(localized: "The watch has the pump. Give \(amount) U by hand if you still want it."))
            return
        }
        guard let reading = latestReading(), Date().timeIntervalSince(reading.date) <= readingMaxAge else {
            warning(.bolus, "Pod change bolus of \(amount) U skipped: no CGM reading from the last 15 min")
            notify(
                String(localized: "No Bolus After the Pod Change"),
                String(localized: "There's no glucose reading from the last 15 minutes, so the \(amount) U wasn't given. Give it by hand if you still want it.")
            )
            return
        }
        guard reading.mgdl >= lowestGlucose else {
            warning(.bolus, "Pod change bolus of \(amount) U skipped: BG \(reading.mgdl) mg/dL is under \(lowestGlucose)")
            notify(
                String(localized: "No Bolus After the Pod Change"),
                String(localized: "Glucose is under 5.0 mmol/L (90 mg/dL), so the \(amount) U wasn't given.")
            )
            return
        }
        info(.bolus, "Pod change bolus: \(amount) U at BG \(reading.mgdl) mg/dL")
        await apsManager.enactBolus(amount: Double(truncating: units as NSNumber), isSMB: false) { success, message in
            if success {
                notify(String(localized: "Bolus After the Pod Change"), String(localized: "\(amount) U given for the new pod."))
            } else {
                warning(.bolus, "Pod change bolus of \(amount) U failed: \(message)")
                notify(
                    String(localized: "Bolus After the Pod Change Failed"),
                    String(localized: "The \(amount) U for the new pod wasn't given: \(message)")
                )
            }
        }
    }

    private static func latestReading() -> (date: Date, mgdl: Int)? {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "podChangeBolus"
        var result: (Date, Int)?
        context.performAndWait {
            let request = GlucoseStored.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate.predicateForOneDayAgo,
                NSPredicate.cgmGlucose
            ])
            request.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)]
            request.fetchLimit = 1
            if let latest = try? context.fetch(request).first, let date = latest.date {
                result = (date, Int(latest.glucose))
            }
        }
        return result
    }

    private static func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "Trio.podChangeBolus", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
