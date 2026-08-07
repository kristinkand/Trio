import Charts
import SwiftUI

/// A small AGP-style percentile chart for one algorithm-adjusted setting (ISF, CR, or AF),
/// aggregated by hour of day across the whole selected duration -- same visual language as the
/// glucose "Ambulatory Glucose Profile" chart (`GlucosePercentileChart`): a light 10-90th
/// percentile band, a darker 25-75th percentile band, and a median line, just scaled down to fit
/// as one of several stacked charts on this tab.
private struct AlgorithmAdjustmentPercentileChart: View {
    let title: String
    let unitLabel: String
    let color: Color
    let hourlyStats: [AlgorithmHourlyStats]

    private var hasAnyData: Bool {
        hourlyStats.contains { $0.hasData }
    }

    // A minimum padding floor keeps the Y range from collapsing to zero width (which leaves the
    // chart frame/axes visible but draws no bands) when every hour has the same value, including
    // the edge case where that value happens to be exactly 0.
    private var minY: Double {
        let values = hourlyStats.filter(\.hasData).map(\.percentile10)
        guard let low = values.min(), low.isFinite else { return 0 }
        let padding = max(abs(low) * 0.1, 0.5)
        return low - padding
    }

    private var maxY: Double {
        let values = hourlyStats.filter(\.hasData).map(\.percentile90)
        guard let high = values.max(), high.isFinite else { return 1 }
        let padding = max(abs(high) * 0.1, 0.5)
        return high + padding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !hasAnyData {
                ContentUnavailableView(
                    String(localized: "No Data"),
                    systemImage: "chart.xyaxis.line"
                )
                .frame(height: 130)
            } else {
                Chart {
                    ForEach(hourlyStats, id: \.hour) { stats in
                        AreaMark(
                            x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                            yStart: .value("10th Percentile", stats.percentile10),
                            yEnd: .value("90th Percentile", stats.percentile90)
                        )
                        .foregroundStyle(color.opacity(0.25))
                        .opacity(stats.hasData ? 1 : 0)

                        AreaMark(
                            x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                            yStart: .value("25th Percentile", stats.percentile25),
                            yEnd: .value("75th Percentile", stats.percentile75)
                        )
                        .foregroundStyle(color.opacity(0.5))
                        .opacity(stats.hasData ? 1 : 0)

                        if stats.hasData {
                            LineMark(
                                x: .value("Hour", Calendar.current.dateForChartHour(stats.hour)),
                                y: .value("Median", stats.median)
                            )
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .foregroundStyle(color)
                        }
                    }
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

/// A single small, stacked line chart for basal rate over time. Values are held constant between
/// loop cycles in real life, so the line is drawn as a step function (`.stepEnd`) rather than
/// interpolated between points. Kept as a plain history line rather than the AGP percentile style
/// used for ISF/CR/AF above, since basal is already a scheduled, step-changing quantity that
/// reads better as "what happened, in order" than as an hour-of-day distribution.
private struct AlgorithmAdjustmentLineChart: View {
    let title: String
    let unitLabel: String
    let color: Color
    let points: [(date: Date, value: Double)]
    let selectedInterval: Stat.StateModel.StatsTimeIntervalWithToday

    private var minY: Double {
        guard let low = points.map(\.value).min(), low.isFinite else { return 0 }
        let padding = max(abs(low) * 0.1, 0.5)
        return low - padding
    }

    private var maxY: Double {
        guard let high = points.map(\.value).max(), high.isFinite else { return 1 }
        let padding = max(abs(high) * 0.1, 0.5)
        return high + padding
    }

    private var axisDateFormat: Date.FormatStyle {
        switch selectedInterval {
        case .today,
             .day:
            return .dateTime.hour()
        case .week:
            return .dateTime.weekday(.abbreviated)
        case .month:
            return .dateTime.day().month(.abbreviated)
        case .total:
            return .dateTime.month(.abbreviated)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if points.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Data"),
                    systemImage: "chart.xyaxis.line"
                )
                .frame(height: 110)
            } else {
                Chart(points, id: \.date) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value(title, point.value)
                    )
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(color)

                    PointMark(
                        x: .value("Time", point.date),
                        y: .value(title, point.value)
                    )
                    .symbolSize(14)
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
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: axisDateFormat, centered: true)
                            .font(.caption2)
                    }
                }
                .frame(height: 110)

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
            AlgorithmAdjustmentPercentileChart(
                title: String(localized: "Insulin Sensitivity Factor (ISF)"),
                unitLabel: "\(units.rawValue) / U",
                color: .glucose,
                hourlyStats: computeAlgorithmHourlyStats(from: points) { point in
                    point.isf.map { Double(truncating: $0.asUnit(units) as NSNumber) }
                }
            )

            Divider()

            AlgorithmAdjustmentPercentileChart(
                title: String(localized: "Carb Ratio (CR)"),
                unitLabel: String(localized: "g carbs / U"),
                color: .carbs,
                hourlyStats: computeAlgorithmHourlyStats(from: points) { point in
                    point.carbRatio.map { Double(truncating: $0 as NSNumber) }
                }
            )

            Divider()

            AlgorithmAdjustmentPercentileChart(
                title: String(localized: "Autosens Ratio (AF)"),
                unitLabel: String(localized: "× of programmed profile"),
                color: .purple,
                hourlyStats: computeAlgorithmHourlyStats(from: points) { point in
                    point.autosensRatio.map { Double(truncating: $0 as NSNumber) }
                }
            )

            Divider()

            AlgorithmAdjustmentLineChart(
                title: String(localized: "Basal Rate"),
                unitLabel: String(localized: "U/hr"),
                color: .basal,
                points: points.compactMap { point in
                    guard let basalRate = point.basalRate else { return nil }
                    return (point.deliverAt, Double(truncating: basalRate as NSNumber))
                },
                selectedInterval: selectedInterval
            )
        }
    }
}
