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

    private func makeRows() -> [Row] {
        guard !initialEntries.isEmpty else { return [Row(timeIndex: 0, valueIndex: 0)] }
        return initialEntries.map { entry in
            let timeIndex = timeValues.firstIndex(of: Double(entry.minutes * 60)) ?? 0
            let valueIndex = valueValues.firstIndex(of: entry.value) ?? closestValueIndex(to: entry.value)
            return Row(timeIndex: timeIndex, valueIndex: valueIndex)
        }
    }

    private func availableTimeIndices(excluding rowID: UUID) -> [Int] {
        let used = Set(rows.filter { $0.id != rowID }.map(\.timeIndex))
        return (0 ..< timeValues.count).filter { !used.contains($0) }
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
            timeIndex = min(last.timeIndex + 1, timeValues.count - 1)
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
                        ForEach(availableTimeIndices(excluding: row.id), id: \.self) { idx in
                            Text(timeLabel(idx)).tag(idx)
                        }
                    }
                    .disabled(rows.first?.id == row.id)
                    .pickerStyle(.menu)

                    Spacer()

                    Picker("Value", selection: $row.valueIndex) {
                        ForEach(valueValues.indices, id: \.self) { idx in
                            Text(valueLabel(valueValues[idx])).tag(idx)
                        }
                    }
                    .pickerStyle(.menu)
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
