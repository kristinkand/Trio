import SwiftUI
import UserNotifications
import WatchKit

@main struct TrioWatchApp: App {
    @WKApplicationDelegateAdaptor(TrioWatchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // the phone link is up at every launch, also the silent background ones
        _ = WatchState.shared
        // restores a running untethered session and its devices
        _ = UntetheredWatchManager.shared
        WatchNotificationHandler.shared.configure()
        WatchLogger.shared.info(.lifecycle, "App launched")
    }

    var body: some Scene {
        WindowGroup {
            TrioMainWatchView()
        }
        .onChange(of: scenePhase) { _, newScenePhase in
            // the phone's state applies at once in the background (before suspension), debounced in front
            WatchState.shared.setAppActive(newScenePhase == .active)
            // wrist down (inactive) or another app (background): either can freeze the app next
            if newScenePhase != .active {
                UntetheredWatchManager.shared.appLeavingScreen()
                WatchG7Reader.shared.appLeavingScreen()
            }
            if newScenePhase == .background {
                WatchLogger.shared.info(.lifecycle, "App moved to background")
                // with the watch's own sensor link the log waits for the phone and a moment clear of the reading,
                // rather than queue up while the phone is away and go over with the rest when it returns
                let untethered = UntetheredWatchManager.shared
                if !untethered.holdsSensorLink {
                    Task { await WatchLogger.shared.flushPersistedLogs() }
                } else if untethered.mayStreamToPhone {
                    Task { await WatchLogger.shared.flushPersistedLogs(queued: true) }
                }
            } else if newScenePhase == .active {
                // in front first, so the recheck holds in the app; a sensor pairing that is due keeps Trio in front
                UntetheredWatchManager.shared.appBecameActive()
                WatchG7Reader.shared.appBecameActive()
                // with the phone away, looking at the watch is the one wake left
                UntetheredWatchManager.shared.recheckCGM()
                // what loops in the background did, without waiting for the phone link
                UntetheredWatchManager.shared.refresh()
                // the phone's newest state, if the one shown is old
                WatchState.shared.refreshIfNeeded()
            }
        }
    }
}

// dev's background refresh while WatchCGMHost reads; unused while the watch's own reader (G7Direct) schedules its own
@MainActor enum WatchBackgroundRefresh {
    private static let interval: TimeInterval = 15 * 60
    private static let settleTimeout: TimeInterval = 5
    private static let settlePoll: TimeInterval = 0.25

    static func schedule() {
        guard !WatchCGMHost.shared.isReadingDirectly else { return }
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: interval),
            userInfo: nil
        ) { error in
            if let error = error {
                WatchLogger.shared.warning(.lifecycle, "Background refresh scheduling failed", error: error)
            }
        }
    }

    static func refresh(_ state: WatchState) async {
        WatchLogger.shared.info(.lifecycle, "Background refresh ran")
        schedule()
        await settle(state)
        state.ingestReceivedApplicationContext()
        await settle(state)
    }

    static func settle(_ state: WatchState) async {
        let deadline = Date(timeIntervalSinceNow: settleTimeout)
        repeat {
            do {
                try await Task.sleep(for: .seconds(settlePoll))
            } catch {
                return
            }
        } while state.isAwaitingDelivery && Date() < deadline
    }
}
