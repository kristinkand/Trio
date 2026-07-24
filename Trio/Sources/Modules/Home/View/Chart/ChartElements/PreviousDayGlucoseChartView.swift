import Charts
import Foundation
import SwiftUI

/// Draws yesterday's BG curve as a dimmed overlay on today's chart, shifted forward
/// by exactly 24h so it lines up with today's clock time. This mirrors LoopFollow's
/// "Show Yesterday's BG" graph overlay, but uses a distinct color instead of gray
/// since the surrounding chart elements are already colored (insulin, carbs, uam...).
struct PreviousDayGlucoseChartView: ChartContent {
    let glucoseData: [GlucoseStored]
    let units: GlucoseUnits

    var body: some ChartContent {
        drawPreviousDayGlucoseChart()
    }

    private func drawPreviousDayGlucoseChart() -> some ChartContent {
        ForEach(glucoseData) { item in
            if let date = item.date {
                let shiftedDate = date.addingTimeInterval(24 * 60 * 60)
                let glucoseToDisplay = units == .mgdL ? Decimal(item.glucose) : Decimal(item.glucose).asMmolL

                LineMark(
                    x: .value("Time", shiftedDate, unit: .second),
                    y: .value("Value", glucoseToDisplay),
                    series: .value("Type", "PreviousDay")
                )
                .foregroundStyle(Color.previousDayGlucose)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .opacity(0.55)
                .interpolationMethod(.monotone)
            }
        }
    }
}
