import SwiftUI

/// Read-only list view for the "Food Impact" stats tab: one row per detected meal event,
/// showing the prebolus/meal timestamps, start/peak/end BG, carbs, prebolus amount, and total
/// bolus insulin used across the ~4h (or longer, if the rise ran late) cycle. Purely a display
/// of data already computed in `MealImpactSetup.swift` -- no dosing, pump, or sensor code here.
struct MealImpactListView: View {
    let events: [MealImpactEvent]
    let units: GlucoseUnits

    /// A fixed viewport height, like the other Stats tabs' cards (Meals: 250, Bolus
    /// Distribution: 280) -- rather than growing with the row count. The list scrolls
    /// internally within this window instead of pushing the rest of the tab down.
    private static let viewportHeight: CGFloat = 350

    var body: some View {
        List {
            ForEach(events) { event in
                MealImpactRow(event: event, units: units)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(height: Self.viewportHeight)
    }
}

private struct MealImpactRow: View {
    let event: MealImpactEvent
    let units: GlucoseUnits

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
                impactStat(
                    title: "End",
                    time: event.endDate.map(Self.timeFormatter.string),
                    value: bg(event.endBG)
                )
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
    }

    @ViewBuilder private func impactStat(title: String, time: String?, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
            if let time = time {
                Text(time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
