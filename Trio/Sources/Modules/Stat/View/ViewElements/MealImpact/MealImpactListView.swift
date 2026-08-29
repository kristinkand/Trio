import SwiftUI

/// List view for the "Food Impact" stats tab: one row per detected meal event, showing the
/// prebolus/meal timestamps, start/peak/end BG, carbs, prebolus amount, total bolus insulin
/// used across the ~4h (or longer, if the rise ran late) cycle, and -- next to the prebolus
/// line -- whether the meal bolus was a Normal, Super, or Reduced Bolus (color-coded to match
/// the carb triangle on the Home chart), for spotting patterns in your own bolus strategy over
/// time. Mostly a display of data already computed in `MealImpactSetup.swift` -- no dosing,
/// pump, or sensor code here -- but a few pieces are user-editable, each backed by its own
/// small UserDefaults-keyed override store:
///   - "Start" and "End" are tappable -- correct either by hand when the auto-detected time
///     doesn't match what the graph actually shows. See `MealImpactStartOverrideStore` /
///     `MealImpactEndOverrideStore`.
///   - A detected secondary rise can be dismissed (the ⓧ next to it) if it's not a real one --
///     see `MealImpactSecondaryRiseOverrideStore`.
///   - A free-text note (e.g. "pizza") can be attached via the note icon -- see
///     `MealImpactNoteStore`.
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
    @State private var showStartEditor = false
    @State private var draftStartDate = Date()
    @State private var showNoteEditor = false
    @State private var draftNote = ""

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

    /// Mirrors the color coding on the Home chart's carb triangle (`CarbView.swift`): pink for
    /// Super Bolus, green for Reduced Bolus, orange otherwise -- so the two features read
    /// consistently at a glance.
    private var bolusTypeLabel: String {
        event.isSuperBolus ? "Super Bolus" : (event.isReducedBolus ? "Reduced Bolus" : "Normal Bolus")
    }

    private var bolusTypeColor: Color {
        event.isSuperBolus ? .pink : (event.isReducedBolus ? .green : .orange)
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

                Button {
                    draftNote = event.note ?? ""
                    showNoteEditor = true
                } label: {
                    Image(systemName: event.note == nil ? "note.text.badge.plus" : "note.text")
                        .font(.caption)
                        .foregroundStyle(event.note == nil ? Color.secondary : Color.accentColor)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Text("\(Int(event.carbs))g carbs")
                if event.fat > 0 || event.protein > 0 {
                    Text("\(Int(event.fat))g fat · \(Int(event.protein))g protein")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let note = event.note {
                Text("📝 \(note)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
            }

            Divider()

            HStack {
                Button {
                    draftStartDate = event.startDate
                    showStartEditor = true
                } label: {
                    impactStat(
                        title: event.startIsOverridden ? "Start (edited)" : "Start",
                        time: Self.timeFormatter.string(from: event.startDate),
                        value: bg(event.startBG),
                        isEditable: true
                    )
                }
                .buttonStyle(.plain)
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
                HStack {
                    Text("Secondary rise at \(Self.timeFormatter.string(from: riseDate)) (\(bg(event.secondaryRiseBG)))")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button {
                        MealImpactSecondaryRiseOverrideStore.dismiss(for: event.id)
                        onOverrideChanged()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
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

                Spacer()

                Label(bolusTypeLabel, systemImage: "arrowtriangle.down.fill")
                    .foregroundStyle(bolusTypeColor)
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
        .sheet(isPresented: $showStartEditor) {
            startEditorSheet
        }
        .sheet(isPresented: $showNoteEditor) {
            noteEditorSheet
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

    @ViewBuilder private var startEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Start time",
                        selection: $draftStartDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } footer: {
                    Text(
                        "Correct this if the detected start (prebolus or meal time) doesn't match what you see on the graph. Moving the start also shifts the peak, secondary-rise, and total-insulin calculations for this meal, since they're all measured from here."
                    )
                }

                if event.startIsOverridden {
                    Section {
                        Button("Reset to Auto-Detected", role: .destructive) {
                            MealImpactStartOverrideStore.clearStart(for: event.id)
                            onOverrideChanged()
                            showStartEditor = false
                        }
                    }
                }
            }
            .navigationTitle("Edit Start Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showStartEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        MealImpactStartOverrideStore.setStart(draftStartDate, for: event.id)
                        onOverrideChanged()
                        showStartEditor = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder private var noteEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. pizza", text: $draftNote)
                } footer: {
                    Text("A short note about this meal -- shown alongside its stats in this list.")
                }

                if event.note != nil {
                    Section {
                        Button("Remove Note", role: .destructive) {
                            MealImpactNoteStore.clearNote(for: event.id)
                            onOverrideChanged()
                            showNoteEditor = false
                        }
                    }
                }
            }
            .navigationTitle("Meal Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNoteEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        MealImpactNoteStore.setNote(draftNote, for: event.id)
                        onOverrideChanged()
                        showNoteEditor = false
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
