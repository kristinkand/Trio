import SwiftUI
import UserNotifications
import WatchKit

@main struct TrioWatchApp: App {
    /// Brings the watch's G7 reader up at every launch, also the silent ones the system makes for a Bluetooth link.
    @WKApplicationDelegateAdaptor(TrioWatchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // the phone link is up at every launch, also the silent background ones
        _ = WatchState.shared
        WatchNotificationHandler.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            TrioMainWatchView()
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .background {
                Task {
                    await WatchLogger.shared.flushPersistedLogs()
                }
            }
        }
    }
}
