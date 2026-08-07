import CoreData
import Foundation

/// A single data point representing the oref algorithm's key adjustable settings
/// (ISF, carb ratio, autosens ratio, and basal rate) at one loop cycle.
///
/// This is a purely read-only, display-only snapshot of values the algorithm already
/// computed and stored on `OrefDetermination` -- nothing here calls into or changes
/// the dosing algorithm, pump, or sensor code.
struct AlgorithmAdjustmentPoint: Identifiable {
    var id: Date { deliverAt }
    let deliverAt: Date
    /// Insulin Sensitivity Factor. Always stored in mg/dL/U; convert for display with `.asUnit(units)`.
    let isf: Decimal?
    /// Carb Ratio (grams of carbs covered by 1 U of insulin).
    let carbRatio: Decimal?
    /// Autosens / Dynamic-ISF adjustment ratio (1.0 = no adjustment).
    let autosensRatio: Decimal?
    /// Algorithm's computed basal rate for this cycle, in U/hr.
    let basalRate: Decimal?
}

/// Percentile statistics for one algorithm-adjusted setting (ISF, CR, or AF), grouped by hour of
/// day across the selected duration. Same shape as `HourlyStats` (the glucose AGP chart's data
/// point) -- basal rate is intentionally excluded, since its step-changing, already-scheduled
/// nature reads better as a plain history line than as an hour-of-day percentile band.
struct AlgorithmHourlyStats: Identifiable {
    let hour: Int
    let median: Double
    let percentile10: Double
    let percentile25: Double
    let percentile75: Double
    let percentile90: Double
    var id: Int { hour }
    /// Whether any determinations at all fell into this hour -- distinguishes a genuine reading
    /// of exactly 0 from "no data for this hour", same convention as the glucose AGP chart uses
    /// (`HourlyStats`/`GlucosePercentileChart` treat `median > 0` as its "has data" signal).
    let hasData: Bool
}

/// Groups `points` by hour of day (0-23) across the whole selected duration and computes
/// percentile statistics per hour -- the same aggregation `AreaChartSetup.computeHourlyStats`
/// does for glucose, generalized with a value-extractor closure so it works for any of the three
/// percentile-able metrics (ISF, CR, AF).
func computeAlgorithmHourlyStats(
    from points: [AlgorithmAdjustmentPoint],
    value: (AlgorithmAdjustmentPoint) -> Double?
) -> [AlgorithmHourlyStats] {
    let calendar = Calendar.current
    let groupedByHour = Dictionary(grouping: points) { calendar.component(.hour, from: $0.deliverAt) }

    return (0 ... 23).map { hour in
        let values = (groupedByHour[hour] ?? []).compactMap(value).sorted()
        guard !values.isEmpty else {
            return AlgorithmHourlyStats(
                hour: hour,
                median: 0,
                percentile10: 0,
                percentile25: 0,
                percentile75: 0,
                percentile90: 0,
                hasData: false
            )
        }

        let count = Double(values.count)
        let median = count.truncatingRemainder(dividingBy: 2) == 0 ?
            (values[Int(count / 2) - 1] + values[Int(count / 2)]) / 2 :
            values[Int(count / 2)]

        return AlgorithmHourlyStats(
            hour: hour,
            median: median,
            percentile10: values[Int(count * 0.10)],
            percentile25: values[Int(count * 0.25)],
            percentile75: values[Int(count * 0.75)],
            percentile90: values[Int(count * 0.90)],
            hasData: true
        )
    }
}

extension Stat.StateModel {
    /// Kicks off fetching + processing of algorithm adjustment history (ISF, CR, AF, basal rate)
    /// for the "Algorithm Adjustments" stats tab.
    func setupAlgorithmAdjustmentStats() {
        Task {
            do {
                let points = try await fetchAlgorithmAdjustmentPoints(for: selectedIntervalForAlgorithmStats)
                await MainActor.run {
                    self.algorithmAdjustmentStats = points
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch algorithm adjustment stats: \(error)")
            }
        }
    }

    /// Fetches `OrefDetermination` records for the selected duration and maps them to lightweight,
    /// read-only chart points.
    ///
    /// Deliberately does NOT filter to `enacted == true` -- this mirrors the predicate the Home
    /// screen's COB/IOB history charts already use (`NSPredicate.determinationsForCobIobCharts`),
    /// so suggested-only cycles still show up and the chart doesn't have gaps. (The "pill"'s own
    /// `enactedDeterminationController` filters to enacted + fetchLimit 1 because it only ever
    /// needs the single current status -- that's a different use case from a history chart.)
    func fetchAlgorithmAdjustmentPoints(for interval: StatsTimeIntervalWithToday) async throws -> [AlgorithmAdjustmentPoint] {
        let taskContext = CoreDataStack.shared.newTaskContext()
        taskContext.name = "StatStateModel.fetchAlgorithmAdjustmentPoints"

        let now = Date()
        let startDate: Date
        switch interval {
        case .day:
            startDate = now.addingTimeInterval(-TimeInterval(hours: 24))
        case .today:
            startDate = Calendar.current.startOfDay(for: now)
        case .week:
            startDate = now.addingTimeInterval(-TimeInterval(hours: 24 * 7))
        case .month:
            startDate = now.addingTimeInterval(-TimeInterval(hours: 24 * 30))
        case .total:
            startDate = now.addingTimeInterval(-TimeInterval(hours: 24 * 90))
        }

        // Fetches full managed objects rather than a properties dictionary. `determinationController`
        // in HomeStateModel.swift (the Home screen's COB/IOB history charts, the precedent this
        // predicate is borrowed from) does the same -- fetching a properties dictionary instead
        // was found to make Core Data substitute the model's default value (0.0) for some
        // Decimal attributes instead of leaving them nil, which collapsed the ISF/CR charts to a
        // zero-width Y range with no visible line. Fetching real objects avoids that entirely.
        let result = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: taskContext,
            predicate: NSPredicate.determinationsForCobIobCharts(since: startDate),
            key: "deliverAt",
            ascending: true,
            batchSize: 100
        )

        return try await taskContext.perform {
            guard let determinations = result as? [OrefDetermination] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return determinations.compactMap { determination -> AlgorithmAdjustmentPoint? in
                guard let deliverAt = determination.deliverAt else { return nil }
                return AlgorithmAdjustmentPoint(
                    deliverAt: deliverAt,
                    isf: determination.insulinSensitivity?.decimalValue,
                    carbRatio: determination.carbRatio?.decimalValue,
                    autosensRatio: determination.sensitivityRatio?.decimalValue,
                    basalRate: determination.rate?.decimalValue
                )
            }
        }
    }
}
