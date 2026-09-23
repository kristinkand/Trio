import Foundation

extension TrioRemoteControl {
    /// Handles a remote "start Weekend Profile" command (see `WeekendProfileStore.activate`).
    /// Rejects the command if a profile has never been saved -- there'd be no basal/ISF schedule to
    /// switch to -- and is a no-op (but still reports success) if Weekend Profile is already active,
    /// matching how `handleStartOverrideCommand` treats re-enacting the same state.
    @MainActor internal func handleStartWeekendProfileCommand(_ payload: CommandPayload) async {
        guard WeekendProfileStore.isConfigured else {
            await logError(
                "Command rejected: Profile hasn't been set up in the app yet. Open Adjustments > Profile and save a profile first.",
                payload: payload
            )
            return
        }
        guard !WeekendProfileStore.isActive else {
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "\(WeekendProfileStore.name) was already active"
            )
            return
        }

        WeekendProfileStore.activate(nightscoutManager: nightscoutManager)
        Foundation.NotificationCenter.default.post(name: .didUpdateWeekendProfileConfiguration, object: nil)

        await logSuccess(
            "Remote command processed successfully. \(payload.humanReadableDescription())",
            payload: payload,
            customNotificationMessage: "\(WeekendProfileStore.name) started"
        )
    }

    /// Handles a remote "stop Weekend Profile" command (see `WeekendProfileStore.deactivate`). A
    /// no-op (but still reports success) if Weekend Profile is already inactive, matching how
    /// `handleCancelOverrideCommand` treats canceling when nothing is running.
    @MainActor internal func handleStopWeekendProfileCommand(_ payload: CommandPayload) async {
        guard WeekendProfileStore.isActive else {
            await logSuccess(
                "Remote command processed successfully. \(payload.humanReadableDescription())",
                payload: payload,
                customNotificationMessage: "\(WeekendProfileStore.name) was already inactive"
            )
            return
        }

        let name = WeekendProfileStore.name
        WeekendProfileStore.deactivate(nightscoutManager: nightscoutManager)
        Foundation.NotificationCenter.default.post(name: .didUpdateWeekendProfileConfiguration, object: nil)

        await logSuccess(
            "Remote command processed successfully. \(payload.humanReadableDescription())",
            payload: payload,
            customNotificationMessage: "\(name) stopped"
        )
    }
}
