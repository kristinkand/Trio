import WatchConnectivity
import WatchKit

/// Receives the launches and background wakes SwiftUI does not surface. Its
/// one job beyond defaults: bring the watch's G7 reader up at every launch
/// (including the silent ones the system makes for a Bluetooth link) and hold
/// the Bluetooth wakes long enough for a reading to arrive.
final class TrioWatchAppDelegate: NSObject, WKApplicationDelegate {
    /// Kept, not just their identities: WatchKit can hand a task over again, and completing one twice crashes.
    private var completed: [WKRefreshBackgroundTask] = []

    func applicationDidFinishLaunching() {
        WatchG7Reader.shared.bootstrap()
        WatchG7Reader.shared.scheduleBackgroundRefresh()
    }

    func applicationDidBecomeActive() {
        WatchG7Reader.shared.appBecameActive()   // before the recheck, so it holds in the app
        WatchG7Reader.shared.noteWake()
    }

    func applicationWillEnterForeground() {
        WatchG7Reader.shared.noteWake()
    }

    /// Implementing this makes every background task ours to complete.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        // Not always on main (EJM0 f858f18): a Bluetooth task can arrive on CoreBluetooth's queue, and all below is
        // main-only. The reader's hold asserts main, so such a task ended the process right at the link-up (Trio
        // 2026-10-18: a new process 5 s after "link up" at 14:10, no reading for hours).
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.handle(backgroundTasks) }
            return
        }
        for task in backgroundTasks {
            switch task {
            case let bluetoothTask as WKBluetoothAlertRefreshBackgroundTask:
                WatchG7Reader.shared.hold(bluetoothTask: bluetoothTask)

            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                // Keep the app awake until WatchConnectivity has delivered
                // what the phone queued, as Apple asks.
                WatchG7Reader.shared.noteWake()
                completeWhenConnectivityIsDelivered(connectivityTask, attempt: 0)

            case let refreshTask as WKApplicationRefreshBackgroundTask:
                WatchG7Reader.shared.noteWake()
                WatchG7Reader.shared.scheduleBackgroundRefresh()
                // A few seconds for the re-check to lodge its request before suspending.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    refreshTask.setTaskCompletedWithSnapshot(false)
                }

            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                snapshotTask.setTaskCompleted(
                    restoredDefaultState: true,
                    estimatedSnapshotExpiration: Date.distantFuture,
                    userInfo: nil
                )

            default:
                WatchG7Reader.shared.noteWake()
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    private func completeOnce(_ task: WKRefreshBackgroundTask) {
        guard !completed.contains(where: { $0 === task }) else { return }
        completed.append(task)
        if completed.count > 128 { completed.removeFirst(32) }
        task.setTaskCompletedWithSnapshot(false)
    }

    /// watchOS gives this wake 15 s of wall clock and ends Trio past it ("WatchConnectivity watchdog transgression",
    /// 8 November 17:46, first tester: launched for it, killed 15.3 s later with content still pending). Up to 15 checks a
    /// second apart reached exactly that. Now it lets go after 10 s at most, and at once when the system ends it
    /// early; what is still pending comes with the next wake.
    private static let connectivityHold: TimeInterval = 10

    private func completeWhenConnectivityIsDelivered(_ task: WKWatchConnectivityRefreshBackgroundTask, attempt: Int) {
        if attempt == 0 {
            task.expirationHandler = { [weak self, weak task] in
                let expire = {
                    Task { await WatchLogger.shared.log("⌚️ Connectivity wake expired by the system", force: true) }
                    if let task { self?.completeOnce(task) }
                }
                if Thread.isMainThread { expire() } else { DispatchQueue.main.async(execute: expire) }
            }
        }
        let session = WCSession.default
        if session.activationState != .activated || !session.hasContentPending
            || TimeInterval(attempt) >= Self.connectivityHold
        {
            if session.hasContentPending {
                Task { await WatchLogger.shared.log("⌚️ Connectivity wake let go after \(attempt) s with content still pending", force: true) }
            }
            completeOnce(task)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.completeWhenConnectivityIsDelivered(task, attempt: attempt + 1)
        }
    }
}
