import Combine
import SwiftUI

extension DeviceAlarms {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var mealTimeReminderService: MealTimeReminderService!
        @Published var podChangeReminderEnabled: Bool = false

        override func subscribe() {
            // the reminder rings as an alarm, so switching it on asks for the alarm permission
            subscribeSetting(\.podChangeReminderEnabled, on: $podChangeReminderEnabled) { podChangeReminderEnabled = $0
            } didSet: { [weak self] enabled in
                guard enabled, let self else { return }
                Task { await self.mealTimeReminderService.requestAuthorization() }
            }
        }
    }
}
