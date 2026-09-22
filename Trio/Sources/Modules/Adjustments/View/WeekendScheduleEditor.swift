import SwiftUI

/// A compact, reusable time-of-day schedule editor: a list of rows, each with its own start time
/// and an absolute value picked from `valueValues` -- the same shape (multiple entries, each with
/// its own start time, absolute values) as the real Basal Profile Editor / ISF Editor, just without
/// their pump-sync/chart/Nightscout-upload machinery, which Weekend Profile doesn't need since it
/// never touches the pump directly and is saved as a single draft by `WeekendProfileSection`'s Save
/// button rather than per-row.
///
/// Used for both Weekend Profile's basal schedule and its ISF schedule -- see `WeekendProfileStore`
/// and `OpenAPS.createProfiles()` for how the saved schedule is substituted into the algorithm.
struct WeekendScheduleEditor: View {
    let title: String
    let footer: String
    let tint: Color
    let valueValues: [Decimal]
    let valueLabel: (Decimal) -> String
    /// (minutes-since-midnight, value) pairs -- the same shape `BasalProfileEntry`/
    /// `InsulinSensitivityEntry` reduce to. Read once on appear; further edits are reported via
    /// `onChange`, not written back into this array.
    let initialEntries: [(minutes: Int, value: Decimal)]
    let onChange: ([(minutes: Int, value: Decimal)]) -> Void

    private let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

    @State private var rows: [Row] = []
    @State private var showInfo = false

    private struct Row: Identifiable, Equatable {
        let id = UUID()
        var timeIndex: Int
        var valueIndex: Int
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func timeLabel(_ index: Int) -> String {
        guard timeValues.indices.contains(index) else { return "--:--" }
        return Self.timeFormatter.string(from: Date(timeIntervalSince1970: timeValues[index]))
    }

    private func closestValueIndex(to value: Decimal) -> Int {
        valueValues.indices.min(by: { abs(valueValues[$0] - value) < abs(valueValues[$1] - value) }) ?? 0
    }

    /// Nearest 30-minute slot to a source entry's start time. The real Basal Profile Editor / ISF
    /// Editor this prefills from allow start times that don't land on this editor's coarser
    /// half-hour grid (e.g. an entry saved at an odd minute) -- round to the closest slot instead
    /// of losing that distinction.
    private func closestTimeIndex(to minutes: Int) -> Int {
        let seconds = Double(minutes * 60)
        return timeValues.indices.min(by: { abs(timeValues[$0] - seconds) < abs(timeValues[$1] - seconds) }) ?? 0
    }

    private func makeRows() -> [Row] {
        guard !initialEntries.isEmpty else { return [Row(timeIndex: 0, valueIndex: 0)] }
        var usedTimeIndices = Set<Int>()
        return initialEntries.map { entry in
            let valueIndex = valueValues.firstIndex(of: entry.value) ?? closestValueIndex(to: entry.value)
            var timeIndex = timeValues.firstIndex(of: Double(entry.minutes * 60)) ?? closestTimeIndex(to: entry.minutes)
            // Two source entries can round to the same slot (e.g. both off-grid and closest to the
            // same half hour). Leaving that collision in place means two rows share a timeIndex,
            // and the Picker below would then render with a selection that isn't among its own
            // options for whichever row lost the slot -- which is what was crashing this screen.
            if usedTimeIndices.contains(timeIndex) {
                timeIndex = (0 ..< timeValues.count).first(where: { !usedTimeIndices.contains($0) }) ?? timeIndex
            }
            usedTimeIndices.insert(timeIndex)
            return Row(timeIndex: timeIndex, valueIndex: valueIndex)
        }
    }

    private func availableTimeIndices(for row: Row) -> [Int] {
        let used = Set(rows.filter { $0.id != row.id }.map(\.timeIndex))
        var indices = (0 ..< timeValues.count).filter { !used.contains($0) }
        // Defense in depth: whatever timeIndex this row is currently bound to must always be
        // among its own Picker's options. A selection value with no matching tag is what SwiftUI
        // was hard-crashing on here -- this makes that combination unrepresentable regardless of
        // how a duplicate slot arises.
        if !indices.contains(row.timeIndex) {
            indices.append(row.timeIndex)
            indices.sort()
        }
        return indices
    }

    private func normalizeAndEmit() {
        var sorted = rows.sorted { $0.timeIndex < $1.timeIndex }
        if var first = sorted.first, first.timeIndex != 0 {
            first.timeIndex = 0
            sorted[0] = first
        }
        if sorted != rows {
            rows = sorted
        }
        onChange(sorted.map { row in
            (minutes: Int(timeValues[row.timeIndex] / 60), value: valueValues[row.valueIndex])
        })
    }

    private func addRow() {
        var timeIndex = 0
        var valueIndex = 0
        if let last = rows.max(by: { $0.timeIndex < $1.timeIndex }) {
            // This is very likely how a real, previously-saved schedule ends up with two rows on
            // the same slot in the first place: if `last` is already at the final slot (23:30),
            // `min(last.timeIndex + 1, timeValues.count - 1)` used to clamp right back onto that
            // same slot instead of picking a genuinely free one. Search forward from `last` for
            // the next open slot, wrapping around, before giving up and reusing `last`'s slot (the
            // schedule is full -- every slot already has a row).
            let used = Set(rows.map(\.timeIndex))
            timeIndex = ((last.timeIndex + 1) ..< timeValues.count).first(where: { !used.contains($0) })
                ?? (0 ..< timeValues.count).first(where: { !used.contains($0) })
                ?? last.timeIndex
            valueIndex = last.valueIndex
        }
        rows.append(Row(timeIndex: timeIndex, valueIndex: valueIndex))
        normalizeAndEmit()
    }

    var body: some View {
        Section {
            ForEach($rows) { $row in
                HStack {
                    Picker("Start", selection: $row.timeIndex) {
                        ForEach(availableTimeIndices(for: row), id: \.self) { idx in
                            Text(timeLabel(idx)).tag(idx)
                        }
                    }
                    .disabled(rows.first?.id == row.id)
                    .pickerStyle(.menu)

                    Spacer()

                    // `valueValues` is meant to always be non-empty (its callers guard for
                    // that), but if it ever isn't, a Picker with zero options still has to bind
                    // `row.valueIndex` to *something* -- and a selection with no matching tag is
                    // exactly what crashed the Start picker above before that fix. Guard here too
                    // rather than trust every future caller to get its own fallback right.
                    if valueValues.isEmpty {
                        Text("No values available").foregroundStyle(.secondary)
                    } else {
                        Picker("Value", selection: $row.valueIndex) {
                            ForEach(valueValues.indices, id: \.self) { idx in
                                Text(valueLabel(valueValues[idx])).tag(idx)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .onChange(of: row.timeIndex) { normalizeAndEmit() }
                .onChange(of: row.valueIndex) { normalizeAndEmit() }
                .swipeActions {
                    if rows.count > 1 {
                        Button(role: .destructive) {
                            rows.removeAll { $0.id == row.id }
                            normalizeAndEmit()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                addRow()
            } label: {
                Label("Add Time", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showInfo) {
                    Text(footer)
                        .padding()
                        .frame(width: 280)
                        .fixedSize(horizontal: false, vertical: true)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        .listRowBackground(tint.opacity(0.15))
        .onAppear {
            if rows.isEmpty {
                rows = makeRows()
            }
        }
    }
}
