import WatchConnectivity
import WatchKit

/// Receives the launches and background wakes SwiftUI does not surface. Its
/// one job beyond defaults: bring the watch's G7 reader up at every launch
/// (including the silent ones the system makes for a Bluetooth link) and hold
/// the Bluetooth wakes long enough for a reading to arrive.
final class TrioWatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchG7Reader.shared.bootstrap()
        WatchG7Reader.shared.scheduleBackgroundRefresh()
    }

    func applicationDidBecomeActive() {
        WatchG7Reader.shared.noteWake()
    }

    func applicationWillEnterForeground() {
        WatchG7Reader.shared.noteWake()
    }

    /// Implementing this makes every background task ours to complete.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
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

    private func completeWhenConnectivityIsDelivered(_ task: WKWatchConnectivityRefreshBackgroundTask, attempt: Int) {
        let session = WCSession.default
        if session.activationState != .activated || !session.hasContentPending || attempt >= 15 {
            task.setTaskCompletedWithSnapshot(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.completeWhenConnectivityIsDelivered(task, attempt: attempt + 1)
        }
    }
}
