import SwiftUI

/// Read-only list view for the "Food Impact" stats tab: one row per detected meal event,
/// showing the prebolus/meal timestamps, start/peak/end BG, carbs, prebolus amount, and total
/// bolus insulin used across the ~4h (or longer, if the rise ran late) cycle. The "End" stat
/// is tappable -- when the auto-detected end doesn't match what the graph actually shows (a
/// slow high-fat/protein rise, say), it can be corrected by hand; see
/// `MealImpactEndOverrideStore` in `MealImpactSetup.swift`. Otherwise purely a display of data
/// already computed there -- no dosing, pump, or sensor code here.
struct MealImpactListView: View {
    let events: [MealImpactEvent]
    let units: GlucoseUnits
    /// Called after the user saves or clears a manual "End" correction, so the caller can
    /// re-fetch events and pick the correction back up -- pass e.g.
    /// `{ state.setupMealImpactStats() }`.
    let onOverrideChanged: () -> Void

    var body: some View {
        List {
            ForEach(events) { event in
                MealImpactRow(event: event, units: units, onOverrideChanged: onOverrideChanged)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(minHeight: CGFloat(events.count) * 92)
    }
}

private struct MealImpactRow: View {
    let event: MealImpactEvent
    let units: GlucoseUnits
    let onOverrideChanged: () -> Void

    @State private var showEndEditor = false
    @State private var draftEndDate = Date()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func bg(_ value: Double?) -> String {
        guard let value = value else { return "–" }
        return Int(value.rounded()).formatted(withUnits: units)
    }

    private func amount(_ value: Double?) -> String {
        guard let value = value else { return "–" }
        return String(format: "%.2f U", value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "fork.knife")
                    .foregroundStyle(Color.orange)
                Text(Self.dateFormatter.string(from: event.mealDate))
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                if event.hasSecondaryRise {
                    Label("2nd rise", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                Text("\(Int(event.carbs))g carbs")
                if event.fat > 0 || event.protein > 0 {
                    Text("\(Int(event.fat))g fat · \(Int(event.protein))g protein")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            HStack {
                impactStat(
                    title: "Start",
                    time: event.prebolusDate.map(Self.timeFormatter.string) ?? Self.timeFormatter.string(from: event.startDate),
                    value: bg(event.startBG)
                )
                Spacer()
                impactStat(
                    title: "Peak",
                    time: event.peakDate.map(Self.timeFormatter.string),
                    value: bg(event.peakBG)
                )
                Spacer()
                Button {
                    draftEndDate = event.endDate ?? event.mealDate
                    showEndEditor = true
                } label: {
                    impactStat(
                        title: event.endIsOverridden ? "End (edited)" : "End",
                        time: event.endDate.map(Self.timeFormatter.string),
                        value: bg(event.endBG),
                        isEditable: true
                    )
                }
                .buttonStyle(.plain)
            }

            if event.hasSecondaryRise, let riseDate = event.secondaryRiseDate {
                Text("Secondary rise at \(Self.timeFormatter.string(from: riseDate)) (\(bg(event.secondaryRiseBG)))")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            HStack(spacing: 12) {
                if let prebolusDate = event.prebolusDate {
                    Label(
                        "Prebolus \(amount(event.prebolusAmount)) at \(Self.timeFormatter.string(from: prebolusDate))",
                        systemImage: "syringe"
                    )
                } else {
                    Label("No prebolus detected", systemImage: "syringe.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Label("Total insulin: \(amount(event.totalInsulin))", systemImage: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showEndEditor) {
            endEditorSheet
        }
    }

    @ViewBuilder private var endEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "End time",
                        selection: $draftEndDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } footer: {
                    Text(
                        "Correct this if the detected end doesn't match what you see on the graph -- e.g. a slow rise that was cut off too early."
                    )
                }

                if event.endIsOverridden {
                    Section {
                        Button("Reset to Auto-Detected", role: .destructive) {
                            MealImpactEndOverrideStore.clearEnd(for: event.id)
                            onOverrideChanged()
                            showEndEditor = false
                        }
                    }
                }
            }
            .navigationTitle("Edit End Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showEndEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        MealImpactEndOverrideStore.setEnd(draftEndDate, for: event.id)
                        onOverrideChanged()
                        showEndEditor = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder private func impactStat(title: String, time: String?, value: String, isEditable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if isEditable {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(isEditable ? Color.accentColor : .primary)
            if let time = time {
                Text(time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
