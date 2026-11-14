import Foundation
import LoopKit
import Swinject
import UserNotifications

#if canImport(AlarmKit)
    import AlarmKit
#endif

extension Notification.Name {
    /// The pending meal-time reminder was set, changed or cleared.
    static let mealTimeReminderDidChange = Notification.Name("mealTimeReminderDidChange")
}

struct PendingMealTimeReminder: Equatable, Codable {
    var fireDate: Date
    var carbs: Decimal
    var bolusAmount: Decimal
    /// The AlarmKit alarm backing this reminder (iOS 26+ path only), persisted so a cancel
    /// after an app restart can still reach it.
    var alarmID: UUID?
}

protocol MealTimeReminderService: AnyObject {
    func requestAuthorization() async

    /// Schedules the reminder `after` from now.
    @discardableResult func scheduleEatReminder(after leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) async -> Bool

    @MainActor func cancelPendingReminders()

    @MainActor var pendingReminder: PendingMealTimeReminder? { get }
}

@Observable final class BaseMealTimeReminderService: MealTimeReminderService, Injectable {
    @ObservationIgnored @Injected() private var trioAlertManager: TrioAlertManager!

    private static let pendingReminderDefaultsKey = "Trio.mealTimeReminderPending"

    /// LoopKit alert identifier for the pre-iOS 26 path.
    private static let alertIdentifier = Alert.Identifier.mealTimeReminderEat

    @MainActor private(set) var pendingReminder: PendingMealTimeReminder?

    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    /// The AlarmKit alarm this service scheduled, so cancel never touches foreign alarms (e.g.
    /// the critical safety alarms that share `AlarmManager.shared`).
    @MainActor private var scheduledAlarmID: UUID? { pendingReminder?.alarmID }

    init(resolver: Resolver) {
        injectServices(resolver)
        Task { await restorePendingReminder() }
    }

    func requestAuthorization() async {
        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                let manager = AlarmManager.shared
                if manager.authorizationState == .notDetermined {
                    _ = try? await manager.requestAuthorization()
                }
            }
        #endif
    }

    @discardableResult func scheduleEatReminder(
        after leadTime: TimeInterval,
        carbs: Decimal,
        bolusAmount: Decimal
    ) async -> Bool {
        guard leadTime > 0 else { return false }

        await cancelPendingReminders()

        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                if let alarmID = await scheduleAlarm(leadTime: leadTime, carbs: carbs, bolusAmount: bolusAmount) {
                    await setPendingReminder(PendingMealTimeReminder(
                        fireDate: Date().addingTimeInterval(leadTime),
                        carbs: carbs,
                        bolusAmount: bolusAmount,
                        alarmID: alarmID
                    ))
                    return true
                }
                // Fall through to a LoopKit alert so the user still gets told when to eat.
            }
        #endif

        issueEatAlert(leadTime: leadTime, carbs: carbs, bolusAmount: bolusAmount)
        await setPendingReminder(PendingMealTimeReminder(
            fireDate: Date().addingTimeInterval(leadTime),
            carbs: carbs,
            bolusAmount: bolusAmount,
            alarmID: nil
        ))
        return true
    }

    @MainActor func cancelPendingReminders() {
        // Must run before setPendingReminder(nil), which is what scheduledAlarmID mirrors.
        #if canImport(AlarmKit)
            if #available(iOS 26.0, *), let alarmID = scheduledAlarmID {
                // cancel clears a scheduled or counting-down alarm; an already alerting one
                // rejects cancel and needs stop instead.
                do {
                    try AlarmManager.shared.cancel(id: alarmID)
                    debug(.bolus, "Meal-time reminder alarm canceled: \(alarmID)")
                } catch {
                    do {
                        try AlarmManager.shared.stop(id: alarmID)
                        debug(.bolus, "Meal-time reminder alarm stopped: \(alarmID)")
                    } catch {
                        warning(.bolus, "Meal-time reminder alarm cancel/stop failed", error: error)
                    }
                }
            }
        #endif

        setPendingReminder(nil)

        trioAlertManager.retractAlert(identifier: Self.alertIdentifier)
    }

    // MARK: - Pending-reminder state (in-app banner)

    @MainActor private func setPendingReminder(_ reminder: PendingMealTimeReminder?) {
        expiryTask?.cancel()
        expiryTask = nil
        pendingReminder = reminder
        // the countdown on the watch's first page follows
        Foundation.NotificationCenter.default.post(name: .mealTimeReminderDidChange, object: nil)

        guard let reminder else {
            UserDefaults.standard.removeObject(forKey: Self.pendingReminderDefaultsKey)
            return
        }

        UserDefaults.standard.set(try? JSONEncoder().encode(reminder), forKey: Self.pendingReminderDefaultsKey)

        expiryTask = Task { [weak self] in
            let delay = reminder.fireDate.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.pendingReminder == reminder else { return }
                self.setPendingReminder(nil)
            }
        }
    }

    /// Reloads the persisted reminder after a cold start, dropping it if it already fired.
    @MainActor private func restorePendingReminder() {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingReminderDefaultsKey),
              let reminder = try? JSONDecoder().decode(PendingMealTimeReminder.self, from: data)
        else { return }

        guard reminder.fireDate > Date() else {
            UserDefaults.standard.removeObject(forKey: Self.pendingReminderDefaultsKey)
            return
        }

        setPendingReminder(reminder)
        debug(
            .bolus,
            "Meal-time reminder restored: fires at \(reminder.fireDate), alarmID \(reminder.alarmID?.uuidString ?? "none")"
        )

        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                let alarmCount = (try? AlarmManager.shared.alarms.count) ?? 0
                debug(.bolus, "Meal-time reminder sees \(alarmCount) system alarm(s)")
            }
        #endif
    }

    // MARK: - AlarmKit (iOS 26+)

    #if canImport(AlarmKit)
        @available(iOS 26.0, *) private func scheduleAlarm(
            leadTime: TimeInterval,
            carbs: Decimal,
            bolusAmount: Decimal
        ) async -> UUID? {
            let manager = AlarmManager.shared

            var authorization = manager.authorizationState
            if authorization == .notDetermined {
                authorization = (try? await manager.requestAuthorization()) ?? .denied
            }
            guard authorization == .authorized else {
                debug(.bolus, "Meal-time reminder alarm not scheduled: AlarmKit authorization is \(authorization)")
                return nil
            }

            let presentation = AlarmPresentation(
                alert: makeAlert(),
                countdown: AlarmPresentation.Countdown(title: "Time to eat in")
            )

            let attributes = AlarmAttributes<MealTimeReminderMetadata>(
                presentation: presentation,
                metadata: MealTimeReminderMetadata(
                    carbs: NSDecimalNumber(decimal: carbs).doubleValue,
                    bolusAmount: NSDecimalNumber(decimal: bolusAmount).doubleValue
                ),
                tintColor: MealTimeReminderStyle.tint
            )

            let configuration = AlarmManager.AlarmConfiguration.timer(
                duration: leadTime,
                attributes: attributes,
                sound: .default
            )

            do {
                let alarmID = UUID()
                _ = try await manager.schedule(id: alarmID, configuration: configuration)
                debug(.bolus, "Meal-time reminder alarm scheduled for \(Int(leadTime / 60)) min")
                return alarmID
            } catch {
                warning(.bolus, "Failed to schedule meal-time reminder alarm", error: error)
                return nil
            }
        }

        /// `AlarmPresentation.Alert`'s initializer without a stop button is iOS 26.1+; on 26.0 we have to
        /// supply one even though the system no longer renders it.
        @available(iOS 26.0, *) private func makeAlert() -> AlarmPresentation.Alert {
            let title: LocalizedStringResource = "Time to eat"

            if #available(iOS 26.1, *) {
                return AlarmPresentation.Alert(title: title)
            } else {
                return AlarmPresentation.Alert(
                    title: title,
                    stopButton: AlarmButton(
                        text: "Eating now",
                        textColor: .white,
                        systemImageName: "fork.knife"
                    )
                )
            }
        }
    #endif

    // MARK: - LoopKit alert (pre-iOS 26)

    /// Routes the reminder through Trio's alert pipeline: an in-app banner while the app is
    /// open, a time-sensitive notification otherwise. Cancellation goes through
    /// `retractAlert`, which also resets the throttler so an immediate re-issue isn't dropped.
    private func issueEatAlert(leadTime: TimeInterval, carbs: Decimal, bolusAmount: Decimal) {
        let content = Alert.Content(
            title: String(localized: "Meal-Time Reminder"),
            body: Self.reminderBody(carbs: carbs, bolusAmount: bolusAmount),
            acknowledgeActionButtonLabel: String(localized: "OK")
        )
        let alert = Alert(
            identifier: Self.alertIdentifier,
            foregroundContent: content,
            backgroundContent: content,
            trigger: .delayed(interval: max(leadTime, 1)),
            interruptionLevel: .timeSensitive,
            sound: .sound(name: "chime.caf")
        )
        trioAlertManager.issueAlert(alert)
    }

    private static func reminderBody(carbs: Decimal, bolusAmount: Decimal) -> String {
        let carbsText = Formatter.integerFormatter.string(from: carbs as NSDecimalNumber) ?? "\(carbs)"
        let bolusText = Formatter.decimalFormatterWithTwoFractionDigits
            .string(from: bolusAmount as NSDecimalNumber) ?? "\(bolusAmount)"

        switch (bolusAmount > 0, carbs > 0) {
        case (true, true):
            return String(
                localized: "Time to eat! You bolused \(bolusText) U for \(carbsText) g of carbs."
            )
        case (true, false):
            return String(localized: "Time to eat! You bolused \(bolusText) U.")
        case (false, true):
            return String(localized: "Time to eat! You logged \(carbsText) g of carbs.")
        case (false, false):
            return String(localized: "Time to eat!")
        }
    }
}

extension Alert.Identifier {
    /// Fallback alert for the pre-iOS 26 meal-time reminder. The user arms the reminder
    /// explicitly, so the alert pipeline lets it pierce the global snooze the same way
    /// critical alerts do (see `BaseTrioAlertManager.issueAlert`).
    static let mealTimeReminderEat = Alert.Identifier(
        managerIdentifier: "Trio.mealTimeReminder",
        alertIdentifier: "eatReminder"
    )
}

// MARK: - Pod change reminder (first tester's own branch)

/// "Change pump!" when the pod is 2 days and 6 hours old, as an alarm that rings until it is stopped (AlarmKit, the
/// same permission as the meal-time reminder: Settings › Trio › Alarms). Scheduled once per pod from its activation;
/// a new pod replaces the alarm. Without that permission, a time-sensitive notification at the same time.
enum PodChangeReminder {
    static let podAge: TimeInterval = (2 * 24 + 6) * 60 * 60

    private static let activationKey = "Trio.podChangeReminder.activatedAt"
    private static let alarmKey = "Trio.podChangeReminder.alarmID"
    private static let notificationID = "Trio.podChangeReminder"

    private static let lock = NSLock()
    private static var isScheduling = false

    /// At each pump update with the pod's activation: schedules for a pod it hasn't seen, and for a known pod whose
    /// reminder is still a notification once the alarm permission is given.
    static func update(activatedAt: Date) {
        let defaults = UserDefaults.standard
        let fireDate = activatedAt.addingTimeInterval(podAge)
        var previous: UUID?
        let known = (defaults.object(forKey: activationKey) as? Date).map { abs($0.timeIntervalSince(activatedAt)) < 1 } ?? false
        if known {
            guard defaults.string(forKey: alarmKey) == nil, fireDate > Date(), alarmsAllowed else { return }
        }
        // claimed before anything changes: a new pod while a schedule runs comes again at the next pump update, with
        // the old pod's alarm still on record to cancel (Claude Fable's review, 14 November)
        guard claim() else { return }
        if !known {
            defaults.set(activatedAt, forKey: activationKey)
            previous = defaults.string(forKey: alarmKey).flatMap(UUID.init(uuidString:))
            defaults.removeObject(forKey: alarmKey)
        }
        Task {
            await schedule(at: fireDate, replacing: previous)
            lock.withLock { isScheduling = false }
        }
    }

    /// The pod was deactivated: its reminder goes, so a pod taken off early doesn't ring later.
    static func podRemoved() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: activationKey) != nil else { return }
        defaults.removeObject(forKey: activationKey)
        let previous = defaults.string(forKey: alarmKey).flatMap(UUID.init(uuidString:))
        defaults.removeObject(forKey: alarmKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        #if canImport(AlarmKit)
            if #available(iOS 26.0, *), let previous { try? AlarmManager.shared.cancel(id: previous) }
        #endif
        debug(.pump, "Pod change reminder: cancelled, no pod")
    }

    private static func claim() -> Bool {
        lock.withLock {
            guard !isScheduling else { return false }
            isScheduling = true
            return true
        }
    }

    private static var alarmsAllowed: Bool {
        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) { return AlarmManager.shared.authorizationState == .authorized }
        #endif
        return false
    }

    private static func schedule(at fireDate: Date, replacing previous: UUID?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                if let previous { try? AlarmManager.shared.cancel(id: previous) }
                guard fireDate > Date() else { return }
                if let id = await scheduleAlarm(at: fireDate) {
                    UserDefaults.standard.set(id.uuidString, forKey: alarmKey)
                    return
                }
            }
        #endif
        guard fireDate > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Change pump!")
        content.body = String(localized: "The pod is 2 days and 6 hours old.")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireDate.timeIntervalSinceNow), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
            debug(.pump, "Pod change reminder: notification for \(fireDate)")
        } catch {
            warning(.pump, "Pod change reminder: notification not scheduled", error: error)
        }
    }

    #if canImport(AlarmKit)
        @available(iOS 26.0, *) private static func scheduleAlarm(at fireDate: Date) async -> UUID? {
            let manager = AlarmManager.shared
            // asked for here too, as the meal-time reminder does: without it the reminder is only a notification
            var authorization = manager.authorizationState
            if authorization == .notDetermined {
                authorization = (try? await manager.requestAuthorization()) ?? .denied
            }
            guard authorization == .authorized else {
                debug(.pump, "Pod change reminder: no alarm, AlarmKit authorization is \(authorization)")
                return nil
            }
            let title: LocalizedStringResource = "Change pump!"
            let alert: AlarmPresentation.Alert
            if #available(iOS 26.1, *) {
                alert = AlarmPresentation.Alert(title: title)
            } else {
                alert = AlarmPresentation.Alert(
                    title: title,
                    stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark")
                )
            }
            let attributes = AlarmAttributes<PodChangeReminderMetadata>(
                presentation: AlarmPresentation(alert: alert),
                metadata: PodChangeReminderMetadata(),
                tintColor: MealTimeReminderStyle.tint
            )
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(fireDate),
                attributes: attributes,
                sound: .default
            )
            do {
                let id = UUID()
                _ = try await manager.schedule(id: id, configuration: configuration)
                debug(.pump, "Pod change reminder: alarm for \(fireDate)")
                return id
            } catch {
                warning(.pump, "Pod change reminder: alarm not scheduled", error: error)
                return nil
            }
        }
    #endif
}

#if canImport(AlarmKit)
    @available(iOS 26.0, *) struct PodChangeReminderMetadata: AlarmMetadata {}
#endif
