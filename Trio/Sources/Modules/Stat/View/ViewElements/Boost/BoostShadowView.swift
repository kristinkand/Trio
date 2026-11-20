import Charts
import SwiftUI

/// Statistics › Boost: the SMBs the loop gave beside the ones Boost would have given (its Shadow line in each loop's
/// reason), as a running total over the day or per day, and per meal Boost recognised, with what glucose did after.
struct BoostShadowView: View {
    let points: [BoostShadowPoint]
    let loopsWithoutLine: Int
    let interval: Stat.StateModel.StatsTimeIntervalWithToday
    let units: GlucoseUnits
    let lowLimit: Decimal

    private var trioTotal: Decimal { points.reduce(0) { $0 + $1.trioSMB } }
    private var boostTotal: Decimal { points.reduce(0) { $0 + $1.boostSMB } }
    private var loopsBoostMore: Int { points.filter { $0.boostSMB > $0.trioSMB }.count }
    private var loopsBoostLess: Int { points.filter { $0.boostSMB < $0.trioSMB }.count }
    private var loopsAsleep: Int { points.filter(\.asleep).count }
    private var isShortSpan: Bool { interval == .today || interval == .day }

    private static let trioColor = Color.insulin
    private static let boostColor = Color.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summary
            if isShortSpan { runningTotalChart } else { perDayChart }
            meals
            if loopsWithoutLine > 0 {
                Text(
                    "\(loopsWithoutLine) loops without Boost's line are left out: Boost was off, or the watch looped in watch mode."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Summary

    private var summary: some View {
        HStack(alignment: .top) {
            total("Trio gave", trioTotal, Self.trioColor)
            Spacer()
            total("Boost would give", boostTotal, Self.boostColor)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Loops").font(.caption).foregroundStyle(.secondary)
                Text("Boost more: \(loopsBoostMore)").font(.caption)
                Text("Boost less: \(loopsBoostLess)").font(.caption)
                Text("Asleep: \(loopsAsleep)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func total(_ title: LocalizedStringKey, _ units: Decimal, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(units.formatted(.number.precision(.fractionLength(2)))) U")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text("as SMB").font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Charts

    /// Today or the last 24 hours: the two running totals, so where Boost would have given more shows as the gap
    /// opening between the lines.
    private var runningTotalChart: some View {
        let sums = runningSums()
        return Chart {
            ForEach(sums, id: \.date) { sum in
                LineMark(x: .value("Time", sum.date), y: .value("Units", sum.trio))
                    .foregroundStyle(by: .value("Source", String(localized: "Trio")))
                    .interpolationMethod(.stepEnd)
                LineMark(x: .value("Time", sum.date), y: .value("Units", sum.boost))
                    .foregroundStyle(by: .value("Source", String(localized: "Boost")))
                    .interpolationMethod(.stepEnd)
            }
        }
        .chartForegroundStyleScale([String(localized: "Trio"): Self.trioColor, String(localized: "Boost"): Self.boostColor])
        .chartYAxisLabel("U, running total")
        .frame(height: 200)
    }

    private func runningSums() -> [(date: Date, trio: Double, boost: Double)] {
        var trio = 0.0
        var boost = 0.0
        return points.map { point in
            trio += NSDecimalNumber(decimal: point.trioSMB).doubleValue
            boost += NSDecimalNumber(decimal: point.boostSMB).doubleValue
            return (point.date, trio, boost)
        }
    }

    /// A week or longer: per day, side by side.
    private var perDayChart: some View {
        Chart {
            ForEach(BoostShadowParser.days(points)) { day in
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Units", NSDecimalNumber(decimal: day.trioSMB).doubleValue)
                )
                .foregroundStyle(by: .value("Source", String(localized: "Trio")))
                .position(by: .value("Source", String(localized: "Trio")))
                BarMark(
                    x: .value("Day", day.day, unit: .day),
                    y: .value("Units", NSDecimalNumber(decimal: day.boostSMB).doubleValue)
                )
                .foregroundStyle(by: .value("Source", String(localized: "Boost")))
                .position(by: .value("Source", String(localized: "Boost")))
            }
        }
        .chartForegroundStyleScale([String(localized: "Trio"): Self.trioColor, String(localized: "Boost"): Self.boostColor])
        .chartYAxisLabel("U per day as SMB")
        .frame(height: 200)
    }

    // MARK: Meals

    @ViewBuilder private var meals: some View {
        let episodes = BoostShadowParser.episodes(points)
        Text("Meals Boost recognised").font(.headline)
        if episodes.isEmpty {
            Text("None in this span yet.").font(.footnote).foregroundStyle(.secondary)
        } else {
            ForEach(episodes) { episode in
                mealRow(episode)
                Divider()
            }
        }
    }

    private func mealRow(_ episode: BoostMealEpisode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(episode.start.formatted(date: isShortSpan ? .omitted : .abbreviated, time: .shortened))
                    .font(.subheadline.bold())
                Text(stageName(episode.furthestState)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(episode.trioSMB.formatted(.number.precision(.fractionLength(2)))) U")
                    .foregroundStyle(Self.trioColor)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                Text("\(episode.boostSMB.formatted(.number.precision(.fractionLength(2)))) U")
                    .foregroundStyle(Self.boostColor)
            }
            .font(.subheadline)
            HStack(spacing: 12) {
                glucoseLabel("Start", episode.startGlucose)
                glucoseLabel("Peak", episode.peakGlucose)
                glucoseLabel("Lowest within 3 h", episode.lowestAfter, warn: (episode.lowestAfter ?? lowLimit) < lowLimit)
            }
            .font(.caption)
        }
    }

    private func glucoseLabel(_ title: LocalizedStringKey, _ value: Decimal?, warn: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(title).foregroundStyle(.secondary)
            Text(value.map { $0.formatted(for: units) } ?? "--")
                .foregroundStyle(warn ? Color.loopRed : Color.primary)
        }
    }

    private func stageName(_ state: String) -> String {
        switch state {
        case "COMMITTED": return String(localized: "committed")
        case "CONFIRMED": return String(localized: "confirmed")
        default: return state.lowercased()
        }
    }
}
