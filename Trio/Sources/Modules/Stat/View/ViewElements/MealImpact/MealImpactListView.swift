import SwiftUI

/// List view for the "Food Impact" stats tab: one row per detected meal event, showing the
/// prebolus/meal timestamps, start/peak/end BG, carbs, prebolus amount, total bolus insulin
/// used across the ~4h (or longer, if the rise ran late) cycle, and -- next to the prebolus
/// line -- whether the meal bolus was a Normal, Super, or Reduced Bolus (color-coded to match
/// the carb triangle on the Home chart), for spotting patterns in your own bolus strategy over
/// time. Mostly a display of data already computed in `MealImpactSetup.swift` -- no dosing,
/// pump, or sensor code here -- but a few pieces are user-editable, each backed by its own
/// small UserDefaults-keyed override store:
///   - "Start", "Peak", and "End" are all tappable -- correct any of them by hand when the
///     auto-detected time doesn't match what the graph actually shows. Only the timestamp is
///     ever editable; the paired BG value is always looked up automatically from the real
///     glucose reading at that time. See `MealImpactStartOverrideStore` /
///     `MealImpactPeakOverrideStore` / `MealImpactEndOverrideStore`.
///   - "Prebolus" (or "No prebolus detected") is tappable too -- record one by hand with its own
///     timestamp and insulin amount when the detector missed a real prebolus (most often because
///     it was given further ahead of the meal than it looks for) or mistimed it. See
///     `MealImpactPrebolusOverrideStore`.
///   - A detected secondary rise can be dismissed (the ⓧ next to it) if it's not a real one --
///     see `MealImpactSecondaryRiseOverrideStore`.
///   - A free-text note (e.g. "pizza") can be attached via the note icon -- see
///     `MealImpactNoteStore`.
///   - A whole event can be deleted (tap the trash icon, then confirm) if it's mis-detected
///     entirely -- see `MealImpactDismissedEventStore`. This only ever hides the event from this
///     list; it never touches the underlying carb/bolus/glucose records.
struct MealImpactListView: View {
    let events: [MealImpactEvent]
    let units: GlucoseUnits
    /// Called after the user saves or clears a manual override (including a delete), so the
    /// caller can re-fetch events and pick the correction back up -- pass e.g.
    /// `{ state.setupMealImpactStats() }`.
    let onOverrideChanged: () -> Void

    /// Event ids the user just deleted, applied to this list immediately. `events` itself only
    /// updates once the caller's `onOverrideChanged()` re-fetch lands (an async Core Data query),
    /// which arrives a moment later than the tap/confirm that triggered it. Once the re-fetch
    /// arrives, `events` no longer contains the dismissed event either (it's filtered server-side
    /// by `MealImpactDismissedEventStore`), so merging the two here is a no-op, not a second
    /// removal.
    @State private var locallyDeletedIDs: Set<UUID> = []

    /// Which event the user tapped delete on, awaiting confirmation. Presenting the confirmation
    /// dialog here -- on the outer view -- rather than on the individual row that's about to be
    /// removed keeps the dialog's own presentation/dismissal from being entangled with that row's
    /// removal.
    @State private var pendingDeleteEvent: MealImpactEvent?

    private var displayedEvents: [MealImpactEvent] {
        events.filter { !locallyDeletedIDs.contains($0.id) }
    }

    var body: some View {
        // Plain ScrollView + LazyVStack, not List -- deleting an event used to go through
        // List/swipeActions, but every row-removal here (even after two rounds of narrowing the
        // change down: decoupling the frame resize, moving the confirmation dialog off the row,
        // disabling the removal's animation) still crashed on device with "Invalid Number Of
        // Items In Section", inside the animated batch-update machinery List's UICollectionView
        // uses under the hood on this iOS version. A LazyVStack never goes through that
        // UICollectionView batch-update path at all for a ForEach change -- it's plain SwiftUI
        // view diffing -- so this sidesteps the whole crash class rather than continuing to
        // narrow down which exact timing detail inside it was the trigger. Delete is now a
        // regular button (the trash icon at the top of each row) instead of a swipe action, since
        // swipeActions only exists on List.
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(displayedEvents) { event in
                    MealImpactRow(
                        event: event,
                        units: units,
                        onRequestDelete: { pendingDeleteEvent = event },
                        onOverrideChanged: onOverrideChanged
                    )
                    if event.id != displayedEvents.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal)
        }
        // Deliberately keyed off `events.count` (the prop from the caller), not
        // `displayedEvents.count`, so this only resizes once the caller's re-fetch actually lands
        // a moment later -- decoupled in time from the delete's own local update.
        .frame(minHeight: CGFloat(events.count) * 92)
        .confirmationDialog(
            "Delete this Food Impact event?",
            isPresented: Binding(
                get: { pendingDeleteEvent != nil },
                set: { isPresented in
                    if !isPresented { pendingDeleteEvent = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let event = pendingDeleteEvent {
                    // No animation for this one -- the row's removal doesn't need to be animated,
                    // and skipping it avoids the animated collection-view batch-update path
                    // entirely (the same path implicated in the crash above).
                    withTransaction(Transaction(animation: nil)) {
                        locallyDeletedIDs.insert(event.id)
                    }
                    MealImpactDismissedEventStore.dismiss(for: event.id)
                    onOverrideChanged()
                }
                pendingDeleteEvent = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteEvent = nil
            }
        } message: {
            // Matches the wording every other override store here uses: nothing about the
            // meal itself (carbs, insulin, glucose history) is touched, only this list.
            Text("This only removes it from the Food Impact list -- your carb entry, boluses, and glucose history are unaffected. This can't be undone from here.")
        }
    }
}

private struct MealImpactRow: View {
    let event: MealImpactEvent
    let units: GlucoseUnits
    /// The trash icon was tapped -- asks the parent `MealImpactListView` to show the delete
    /// confirmation (see `pendingDeleteEvent` there), rather than presenting it from this row.
    let onRequestDelete: () -> Void
    let onOverrideChanged: () -> Void

    @State private var showEndEditor = false
    @State private var draftEndDate = Date()
    @State private var showStartEditor = false
    @State private var draftStartDate = Date()
    @State private var showPeakEditor = false
    @State private var draftPeakDate = Date()
    @State private var showNoteEditor = false
    @State private var draftNote = ""
    @State private var showPrebolusEditor = false
    @State private var draftPrebolusDate = Date()
    @State private var draftPrebolusAmount: Decimal = 0

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

                Button {
                    onRequestDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
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
                Button {
                    draftPeakDate = event.peakDate ?? event.mealDate
                    showPeakEditor = true
                } label: {
                    impactStat(
                        title: event.peakIsOverridden ? "Peak (edited)" : "Peak",
                        time: event.peakDate.map(Self.timeFormatter.string),
                        value: bg(event.peakBG),
                        isEditable: true
                    )
                }
                .buttonStyle(.plain)
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
                Button {
                    draftPrebolusDate = event.prebolusDate ?? event.mealDate
                    draftPrebolusAmount = event.prebolusAmount.map { Decimal($0) } ?? 0
                    showPrebolusEditor = true
                } label: {
                    HStack(spacing: 3) {
                        if let prebolusDate = event.prebolusDate {
                            Label(
                                "Prebolus\(event.prebolusIsOverridden ? " (edited)" : "") \(amount(event.prebolusAmount)) at \(Self.timeFormatter.string(from: prebolusDate))",
                                systemImage: "syringe"
                            )
                        } else {
                            Label("No prebolus detected", systemImage: "syringe.fill")
                        }
                        Image(systemName: "pencil")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)

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
        .sheet(isPresented: $showPeakEditor) {
            peakEditorSheet
        }
        .sheet(isPresented: $showNoteEditor) {
            noteEditorSheet
        }
        .sheet(isPresented: $showPrebolusEditor) {
            prebolusEditorSheet
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

    @ViewBuilder private var peakEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Peak time",
                        selection: $draftPeakDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } footer: {
                    Text(
                        "Correct this if the detected peak doesn't match the true high point on the graph -- e.g. a brief sensor-noise spike outscored the real one. Only the timestamp is editable; the BG value is looked up automatically from your actual glucose reading at that time. Moving the peak also reshapes the secondary-rise search and the auto-detected end for this meal, since both are measured from here."
                    )
                }

                if event.peakIsOverridden {
                    Section {
                        Button("Reset to Auto-Detected", role: .destructive) {
                            MealImpactPeakOverrideStore.clearPeak(for: event.id)
                            onOverrideChanged()
                            showPeakEditor = false
                        }
                    }
                }
            }
            .navigationTitle("Edit Peak Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPeakEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        MealImpactPeakOverrideStore.setPeak(draftPeakDate, for: event.id)
                        onOverrideChanged()
                        showPeakEditor = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Whether `draftPrebolusAmount` is a usable insulin amount -- Save is disabled otherwise so
    /// a stray/empty entry can't record a nonsensical prebolus.
    private var draftPrebolusAmountIsValid: Bool { draftPrebolusAmount > 0 }

    /// Locale-aware, same pattern as the app's other numeric entry fields (see
    /// `TextFieldWithToolBar`) -- a plain `TextField` + `Double(string)` (what this used to be)
    /// only ever parses "." as the decimal separator, so on any device set to a locale that
    /// types a comma for decimals, entering e.g. "1,50" silently fails to parse and Save stays
    /// disabled, while a whole number like "1" still works by accident (no separator involved).
    private var prebolusAmountFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumIntegerDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }

    @ViewBuilder private var prebolusEditorSheet: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Prebolus time",
                        selection: $draftPrebolusDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextFieldWithToolBar(
                            text: $draftPrebolusAmount,
                            placeholder: "e.g. 1.50",
                            numberFormatter: prebolusAmountFormatter,
                            unitsText: "U"
                        )
                    }
                } footer: {
                    Text(
                        "Record this if you gave a prebolus that wasn't detected -- most often because it was given further ahead of the meal than the detector looks for. This also corrects this meal's tracked start time (and everything measured from it: peak, secondary rise, total insulin), the same as editing Start directly would."
                    )
                }

                if event.prebolusIsOverridden {
                    Section {
                        Button("Reset to Auto-Detected", role: .destructive) {
                            MealImpactPrebolusOverrideStore.clearPrebolus(for: event.id)
                            onOverrideChanged()
                            showPrebolusEditor = false
                        }
                    }
                }
            }
            .navigationTitle("Edit Prebolus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showPrebolusEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard draftPrebolusAmountIsValid else { return }
                        MealImpactPrebolusOverrideStore.setPrebolus(
                            date: draftPrebolusDate,
                            amount: Double(truncating: draftPrebolusAmount as NSNumber),
                            for: event.id
                        )
                        onOverrideChanged()
                        showPrebolusEditor = false
                    }
                    .disabled(!draftPrebolusAmountIsValid)
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
