import Charts
import SwiftUI

/// A single small, stacked line chart for one algorithm-adjusted setting (ISF, CR, AF, or basal
/// rate) over time. Values are held constant between loop cycles in real life, so the line is
/// drawn as a step function (`.stepEnd`) rather than interpolated between points.
private struct AlgorithmAdjustmentLineChart: View {
    let title: String
    let unitLabel: String
    let color: Color
    let points: [(date: Date, value: Double)]
    let selectedInterval: Stat.StateModel.StatsTimeIntervalWithToday

    private var minY: Double {
        guard let low = points.map(\.value).min() else { return 0 }
        let padding = abs(low) * 0.1
        return low - padding
    }

    private var maxY: Double {
        guard let high = points.map(\.value).max() else { return 1 }
        let padding = abs(high) * 0.1
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
            AlgorithmAdjustmentLineChart(
                title: String(localized: "Insulin Sensitivity Factor (ISF)"),
                unitLabel: "\(units.rawValue) / U",
                color: .glucose,
                points: points.compactMap { point in
                    guard let isf = point.isf else { return nil }
                    return (point.deliverAt, Double(truncating: isf.asUnit(units) as NSNumber))
                },
                selectedInterval: selectedInterval
            )

            Divider()

            AlgorithmAdjustmentLineChart(
                title: String(localized: "Carb Ratio (CR)"),
                unitLabel: String(localized: "g carbs / U"),
                color: .carbs,
                points: points.compactMap { point in
                    guard let carbRatio = point.carbRatio else { return nil }
                    return (point.deliverAt, Double(truncating: carbRatio as NSNumber))
                },
                selectedInterval: selectedInterval
            )

            Divider()

            AlgorithmAdjustmentLineChart(
                title: String(localized: "Autosens Ratio (AF)"),
                unitLabel: String(localized: "× of programmed profile"),
                color: .purple,
                points: points.compactMap { point in
                    guard let autosensRatio = point.autosensRatio else { return nil }
                    return (point.deliverAt, Double(truncating: autosensRatio as NSNumber))
                },
                selectedInterval: selectedInterval
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
