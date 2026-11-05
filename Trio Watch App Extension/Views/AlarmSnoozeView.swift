import SwiftUI

struct AlarmSnoozeView: View {
    let state: WatchState

    @State private var showingSnoozeOptions = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            // measure from now, so calculation is not based off stale tick date
            // cf. https://github.com/nightscout/Trio/issues/1381
            let now = max(context.date, Date())
            let isSnoozed = state.snoozeUntilDate > now
            let remainingMinutes = max(Int(ceil(state.snoozeUntilDate.timeIntervalSince(now) / 60)), 0)

            VStack {
                Button {
                    showingSnoozeOptions = true
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: isSnoozed ? "bell.slash.fill" : "bell.fill")
                            .font(.title2)
                        if isSnoozed {
                            Text(remainingMinutes < 120 ? "\(remainingMinutes) m" : "\((remainingMinutes + 30) / 60) h")
                                .font(.headline).fontWeight(.bold).fontDesign(.rounded)
                        }
                    }
                    .foregroundStyle(isSnoozed ? Color.secondary : Color.primary)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.4), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Text(
                    isSnoozed
                        ? String(
                            format: String(localized: "Snoozed until %@"),
                            AlarmSnoozeUntilView.untilText(state.snoozeUntilDate)
                        )
                        : String(localized: "Alarms active")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Alarms"))
            .accessibilityValue(Text(
                isSnoozed
                    ? String(
                        format: String(localized: "snoozed, %d minutes remaining", comment: "Accessibility: alarm snooze"),
                        remainingMinutes
                    )
                    : String(localized: "active", comment: "Accessibility: alarms active")
            ))
            .accessibilityHint(Text(String(localized: "Opens snooze options", comment: "Accessibility hint")))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showingSnoozeOptions = true }
        }
        .sheet(isPresented: $showingSnoozeOptions) {
            AlarmSnoozeOptionsView(state: state) {
                showingSnoozeOptions = false
            }
        }
    }
}

struct AlarmSnoozeOptionsView: View {
    let state: WatchState
    var onDismiss: () -> Void

    var body: some View {
        NavigationView {
            List {
                if state.snoozeUntilDate > Date() {
                    Button {
                        state.sendSnoozeRequest(minutes: 0)
                        onDismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "alarm.waves.left.and.right.fill")
                            Text("End Snooze")
                        }
                    }
                    .foregroundColor(.white)
                    .listRowBackground(
                        Color.loopRed
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                }

                ForEach(NotificationResponseAction.allCases, id: \.self) { action in
                    Button(action.localizedTitle) {
                        state.sendSnoozeRequest(minutes: action.minutes)
                        onDismiss()
                    }
                }

                NavigationLink("Until…") {
                    AlarmSnoozeUntilView(state: state, onDismiss: onDismiss)
                }
            }
            .navigationTitle("Snooze Alerts")
        }
    }
}

/// A chosen end for the snooze, as LoopFollow offers: sent as the minutes until then, which the phone already takes.
struct AlarmSnoozeUntilView: View {
    let state: WatchState
    var onDismiss: () -> Void

    /// Days from today, the hour and the minute (in 5-minute steps), each chosen on its own screen with the crown,
    /// as the watch's own Alarms app does: the system date picker squashed the date on a watch screen.
    @State private var day: Int
    @State private var hour: Int
    @State private var minute: Int

    /// How far ahead the day can be.
    static let days = 14

    init(state: WatchState, onDismiss: @escaping () -> Void) {
        self.state = state
        self.onDismiss = onDismiss
        // 8 hours ahead, on the next 5 minutes
        let ahead = Date().addingTimeInterval(8 * 60 * 60).timeIntervalSinceReferenceDate
        let start = Date(timeIntervalSinceReferenceDate: (ahead / 300).rounded(.up) * 300)
        let calendar = Calendar.current
        _day = State(initialValue: min(calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: start)
        ).day ?? 0, Self.days - 1))
        let parts = calendar.dateComponents([.hour, .minute], from: start)
        _hour = State(initialValue: parts.hour ?? 0)
        _minute = State(initialValue: (parts.minute ?? 0) / 5 * 5)
    }

    private var until: Date {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }

    var body: some View {
        List {
            NavigationLink {
                Picker("Day", selection: $day) {
                    ForEach(0 ..< Self.days, id: \.self) { offset in
                        Text(Self.dayLabel(offset)).tag(offset)
                    }
                }
                .pickerStyle(.wheel)
                .navigationTitle("Day")
            } label: {
                LabeledContent("Day", value: Self.dayLabel(day))
            }

            NavigationLink {
                // tap the hours or the minutes, then turn the crown
                HStack(spacing: 4) {
                    Picker("Hour", selection: $hour) {
                        ForEach(0 ..< 24, id: \.self) { value in
                            Text(Self.hourLabel(value)).tag(value)
                        }
                    }
                    Text(":").font(.title2)
                    Picker("Minute", selection: $minute) {
                        ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { value in
                            Text(String(format: "%02d", value)).tag(value)
                        }
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .navigationTitle("Time")
            } label: {
                LabeledContent("Time", value: until.formatted(date: .omitted, time: .shortened))
            }

            Button {
                let minutes = Int(ceil(until.timeIntervalSinceNow / 60))
                guard minutes > 0 else { return }
                state.sendSnoozeRequest(minutes: minutes)
                onDismiss()
            } label: {
                Text(
                    until > Date()
                        ? String(format: String(localized: "Snooze until %@"), Self.untilText(until))
                        : String(localized: "That time has passed")
                )
            }
            .disabled(until <= Date())
        }
        .navigationTitle("Until")
    }

    static func dayLabel(_ offset: Int) -> String {
        let calendar = Calendar.current
        switch offset {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        default:
            let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: Date())) ?? Date()
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    /// In the watch's own clock style: "07" or "7 AM".
    static func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour())
    }

    /// The time alone today, with the date on another day.
    static func untilText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}
