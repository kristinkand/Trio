import SwiftUI
import Swinject

/// Shared "Snooze All" sheet. Used from Notifications settings and the home
/// glucose long-press. Wraps `TrioAlertManager.applySnooze` directly — no
/// router / module hop.
struct SnoozeAlertsSheetView: View {
    let resolver: Resolver
    @Binding var isPresented: Bool

    @State private var snoozeUntilDate: Date = .distantPast
    /// "Until": a chosen end, as LoopFollow's snooze offers, beyond the fixed durations.
    @State private var untilPick = Date().addingTimeInterval(8 * 60 * 60)

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        NavigationStack {
            List {
                if snoozeUntilDate > Date() {
                    Section {
                        HStack {
                            Image(systemName: "moon.zzz.fill").foregroundStyle(.tint)
                            Text(String(
                                format: String(localized: "Snoozed until %@"),
                                Self.untilText(snoozeUntilDate)
                            ))
                                .font(.headline)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            endSnoozeAction
                        }
                        .listRowBackground(Color.chart)
                    } footer: {
                        HStack {
                            Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                            Text("Swipe left to end snooze.")
                        }
                    }
                }
                Section(footer: Text(
                    "Pick a duration to mute every Trio alarm. Critical alerts (e.g. occlusion, urgent low) still pierce the snooze."
                )) {
                    ForEach(NotificationResponseAction.allCases, id: \.self) { action in
                        Button {
                            applySnooze(action.duration)
                        } label: {
                            HStack {
                                Text(action.localizedTitle).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.footnote)
                            }
                        }
                    }
                }.listRowBackground(Color.chart)
                Section(footer: Text("Snooze every Trio alarm until the time you choose, also on another day.")) {
                    DatePicker(
                        "Until",
                        selection: $untilPick,
                        in: Date().addingTimeInterval(60)...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Button {
                        applySnooze(untilPick.timeIntervalSinceNow)
                    } label: {
                        Text(String(format: String(localized: "Snooze until %@"), Self.untilText(untilPick)))
                    }
                    .disabled(untilPick <= Date())
                }.listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Snooze Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { isPresented = false }
                }
            }
            .onAppear {
                snoozeUntilDate = UserDefaults.standard
                    .object(forKey: "UserNotificationsManager.snoozeUntilDate") as? Date ?? .distantPast
            }
        }
    }

    /// The time alone today, with the date on another day.
    static func untilText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    private var endSnoozeAction: some View {
        Button(role: .destructive) {
            endSnooze()
        } label: {
            Label("End Snooze", systemImage: "alarm.waves.left.and.right.fill")
        }
        .tint(.red)
    }

    private func applySnooze(_ duration: TimeInterval) {
        let trioAlertManager = resolver.resolve(TrioAlertManager.self)
        Task { @MainActor in
            await trioAlertManager?.applySnooze(for: duration)
            snoozeUntilDate = Date().addingTimeInterval(duration)
            isPresented = false
        }
    }

    private func endSnooze() {
        let trioAlertManager = resolver.resolve(TrioAlertManager.self)
        Task { @MainActor in
            await trioAlertManager?.applySnooze(for: 0)
            snoozeUntilDate = Date().addingTimeInterval(0)
        }
    }
}
