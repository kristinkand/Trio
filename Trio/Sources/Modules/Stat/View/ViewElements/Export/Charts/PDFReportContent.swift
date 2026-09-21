import SwiftUI

/// PDF page content for the "Glucose Distribution" export.
/// Reuses the same chart/stat components shown in the on-screen Statistics sheet.
struct GlucoseDistributionPDFContent: View {
    let glucose: [GlucoseStored]
    let glucoseRangeStats: [GlucoseRangeStats]
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit
    let timeInRangeType: TimeInRangeType

    var body: some View {
        GlucoseDistributionChart(
            glucose: glucose,
            highLimit: highLimit,
            lowLimit: lowLimit,
            units: units,
            glucoseRangeStats: glucoseRangeStats,
            timeInRangeType: timeInRangeType
        )

        Divider()

        VStack(spacing: 16) {
            GlucoseSectorChart(
                highLimit: highLimit,
                units: units,
                glucose: glucose,
                timeInRangeType: timeInRangeType,
                showChart: true
            )

            Divider()

            GlucoseMetricsView(
                units: units,
                eA1cDisplayUnit: eA1cDisplayUnit,
                glucose: glucose
            )
        }
    }
}

/// PDF page content for the "Glucose Percentile" (AGP) export.
/// Reuses the same AGP chart shown in the on-screen Statistics sheet, plus the same
/// percentage-distribution summary (sector chart + metrics row) that the "Glucose Distribution"
/// export already includes above -- the on-screen AGP chart never had this attached, but the PDF
/// report is meant to read as a standalone page, so it gets the same summary the distribution
/// export gets.
struct GlucosePercentilePDFContent: View {
    let glucose: [GlucoseStored]
    let highLimit: Decimal
    let timeInRangeType: TimeInRangeType
    let units: GlucoseUnits
    let hourlyStats: [HourlyStats]
    let eA1cDisplayUnit: EstimatedA1cDisplayUnit

    var body: some View {
        GlucosePercentileChart(
            glucose: glucose,
            highLimit: highLimit,
            timeInRangeType: timeInRangeType,
            units: units,
            hourlyStats: hourlyStats,
            isToday: false
        )

        Divider()

        VStack(spacing: 16) {
            GlucoseSectorChart(
                highLimit: highLimit,
                units: units,
                glucose: glucose,
                timeInRangeType: timeInRangeType,
                showChart: true
            )

            Divider()

            GlucoseMetricsView(
                units: units,
                eA1cDisplayUnit: eA1cDisplayUnit,
                glucose: glucose
            )
        }
    }
}

/// PDF page content for the "Looping Performance" export.
/// Reuses the same static bar chart and stats row shown in the on-screen Statistics sheet.
struct LoopingPerformancePDFContent: View {
    let loopStatRecords: [LoopStatRecord]
    let selectedInterval: Stat.StateModel.StatsTimeIntervalWithToday
    let loopStats: [LoopStatsProcessedData]

    var body: some View {
        LoopBarChartView(
            loopStatRecords: loopStatRecords,
            selectedInterval: selectedInterval,
            statsData: loopStats
        )

        Divider()

        LoopStatsView(statsData: loopStats)
    }
}
