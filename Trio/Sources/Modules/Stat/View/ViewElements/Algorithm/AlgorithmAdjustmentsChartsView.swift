import Charts
import SwiftUI

/// A small "dotted" chart for one algorithm-adjusted setting (ISF, CR, AF, or basal rate): one
/// dot per hour of day, at that hour's median value across the whole selected duration. All four
/// metrics share this same hour-of-day treatment for visual consistency.
///
/// An earlier version drew this as AGP-style percentile bands (`AreaMark`) with a smooth median
/// `LineMark`, colored with this app's semantic `Color.glucose`/`Color.carbs` values. Both of
/// those colors turned out to reference asset-catalog color sets that don't actually exist
/// anywhere in this project -- unlike `Color.basal` (a real asset) or `Color.purple` (a system
/// color), so anything drawn with them rendered fully transparent. Landing on plain `PointMark`
/// dots with real, working colors sidesteps that and reads more clearly at this chart's size.
private struct AlgorithmAdjustmentDotChart: View {
    let title: String
    let unitLabel: String
    let color: Color
    let hourlyStats: [AlgorithmHourlyStats]

    private var dataPoints: [AlgorithmHourlyStats] {
        hourlyStats.filter(\.hasData)
    }

    private var minY: Double {
        guard let low = dataPoints.map(\.median).min(), low.isFinite else { return 0 }
        let padding = max(abs(low) * 0.1, 0.5)
        return low - padding
    }

    private var maxY: Double {
        guard let high = dataPoints.map(\.median).max(), high.isFinite else { return 1 }
        let padding = max(abs(high) * 0.1, 0.5)
        return high + padding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if dataPoints.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Data"),
                    systemImage: "chart.xyaxis.line"
                )
                .frame(height: 130)
            } else {
                Chart(dataPoints, id: \.hour) { stats in
                    PointMark(
                        x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                        y: .value(title, stats.median)
                    )
                    .symbolSize(18)
                    .foregroundStyle(color)
                }
                .chartYScale(domain: minY ... maxY)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        if let val = value.as(Double.self) {
                            AxisValueLabel {
                                Text(val.formatted(.number.precision(.fractionLength(0 ... 1))))
                                    .font(.caption2)
                            }
                            AxisGridLine()
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                        if value.as(Date.self) != nil {
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                                .font(.caption2)
                            AxisGridLine()
                        }
                    }
                }
                .frame(height: 130)

                Text(unitLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Stacks the four algorithm-adjustment history charts (ISF, CR, AF, basal rate) for the
/// "Algorithm Adjustments" stats tab. Purely a display component built from already-stored
/// `OrefDetermination` values -- reads history only, no dosing/pump/sensor code involved.
struct AlgorithmAdjustmentsChartsView: View {
    let points: [AlgorithmAdjustmentPoint]
    let units: GlucoseUnits
    let selectedInterval: Stat.StateModel.StatsTimeIntervalWithToday

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            AlgorithmAdjustmentDotChart(
                title: String(localized: "Insulin Sensitivity Factor (ISF)"),
                unitLabel: "\(units.rawValue) / U",
                color: .blue,
                hourlyStats: computeAlgorithmHourlyStats(from: points) { point in
                    point.isf.map { Double(truncating: $0.asUnit(units) as NSNumber) }
                }
            )

            Divider()

            AlgorithmAdjustmentDotChart(
                title: String(localized: "Carb Ratio (CR)"),
                unitLabel: String(localized: "g carbs / U"),
                color: .orange,
                hourlyStats: computeAlgorithmHourlyStats(from: points) { point in
                    point.carbRatio.map { Double(truncating: $0 as NSNumber) }
                }
            )

            Divider()

            AlgorithmAdjustmentDotChart(
                title: String(localized: "Autosens Ratio (AF)"),
                unitLabel: String(localized: "× of programmed profile"),
                color: .purple,
                hourlyStats: computeAlgorithmHourlyStats(from: points) { point in
                    point.autosensRatio.map { Double(truncating: $0 as NSNumber) }
                }
            )

            Divider()

            AlgorithmAdjustmentDotChart(
                title: String(localized: "Basal Rate"),
                unitLabel: String(localized: "U/hr"),
                color: .basal,
                hourlyStats: computeAlgorithmHourlyStats(from: points) { point in
                    point.basalRate.map { Double(truncating: $0 as NSNumber) }
                }
            )
        }
    }
}
