import Foundation
import UserNotifications
import WatchConnectivity

final class WatchNotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotificationHandler()

    override private init() {
        super.init()
    }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories(on: center)
    }

    private func registerCategories(on center: UNUserNotificationCenter) {
        center.getNotificationCategories { existingCategories in
            let glucoseCategory = NotificationCategoryFactory.createGlucoseCategory()

            var categories = existingCategories
            categories.update(with: glucoseCategory)
            // the heart-rate offer's one tap (c230)
            categories.update(with: UNNotificationCategory(
                identifier: UntetheredWatchManager.activityOfferCategory,
                actions: [UNNotificationAction(
                    identifier: UntetheredWatchManager.activityOfferStartAction,
                    title: String(localized: "Start"),
                    options: []
                )],
                intentIdentifiers: []
            ))
            // UNUserNotificationCenter methods should be called on main thread
            Task { @MainActor in
                center.setNotificationCategories(categories)
            }
        }
    }

    /// Shows the watch's own alerts even when Trio is open on the wrist: the reader's (raised while the iPhone is out
    /// of reach) and untethered mode's, which are the only alarms while the watch loops. Everything else keeps the
    /// system's default handling.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let id = notification.request.identifier
        if id.hasPrefix(UntetheredWatchManager.notificationPrefix)
            || id.hasPrefix(WatchAlarms.notificationPrefix)
        {
            completionHandler([.banner, .list, .sound])
        } else {
            completionHandler([])
        }
    }

    /// UNUserNotificationCenterDelegate method called when user interacts with a notification on watch.
    /// This can be called off the main thread. WCSession.transferUserInfo is thread-safe.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        // a tap on a notice that asks for action ("Watch Took Over: Open Trio", pairing) answers it: no reminders,
        // whether or not Trio counts as in front by the time it runs (31 October, 11:09)
        let id = response.notification.request.identifier
        if id.hasPrefix(UntetheredWatchManager.notificationPrefix) {
            ActionNotice.clearReminders()
            let title = response.notification.request.content.title
            let how = response.actionIdentifier == UNNotificationDefaultActionIdentifier ? "opened" : "dismissed or other action"
            Task { await WatchLogger.shared.log("⌚️ Notice tapped: \(title) (\(how))", force: true) }
        }

        if response.actionIdentifier == UntetheredWatchManager.activityOfferStartAction,
           let name = response.notification.request.content.userInfo[UntetheredWatchManager.activityOfferNameKey] as? String
        {
            Task { @MainActor in UntetheredWatchManager.shared.startOfferedOverride(named: name) }
            return
        }

        guard let action = NotificationResponseAction(rawValue: response.actionIdentifier) else { return }
        sendSnoozeRequest(minutes: action.minutes)
    }

    /// Sends snooze request to iPhone via WatchConnectivity.
    /// WCSession.transferUserInfo is thread-safe and can be called from any thread.
    /// Relies on the watch app's WCSession owner (e.g., WatchState) to handle
    /// session activation and delegate management.
    /// A duration of 0 ends the active snooze.
    func sendSnoozeRequest(minutes: Int) {
        guard WCSession.isSupported() else { return }
        // at once on the watch too: its own alarms snooze while the phone is away
        DispatchQueue.main.async {
            WatchState.shared.snoozeUntilDate = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes) * 60) : .distantPast
        }

        let payload: [String: Any] = [WatchMessageKeys.snoozeDuration: minutes]
        let session = WCSession.default

        // Try sendMessage first if session is reachable and activated (faster, immediate delivery)
        // Fall back to transferUserInfo if not reachable or if sendMessage fails
        if session.isReachable, session.activationState == .activated {
            session.sendMessage(payload, replyHandler: nil) { _ in
                // Fallback to transferUserInfo if sendMessage fails
                session.transferUserInfo(payload)
            }
        } else {
            // Session not reachable or not activated - use transferUserInfo (queued delivery)
            session.transferUserInfo(payload)
        }
    }
}
