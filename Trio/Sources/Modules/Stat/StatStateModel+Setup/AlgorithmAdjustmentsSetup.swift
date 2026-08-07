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

        let result = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: taskContext,
            predicate: NSPredicate.determinationsForCobIobCharts(since: startDate),
            key: "deliverAt",
            ascending: true,
            batchSize: 100,
            propertiesToFetch: ["deliverAt", "insulinSensitivity", "carbRatio", "sensitivityRatio", "rate"]
        )

        return try await taskContext.perform {
            guard let rows = result as? [[String: Any]] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return rows.compactMap { row -> AlgorithmAdjustmentPoint? in
                guard let deliverAt = row["deliverAt"] as? Date else { return nil }
                return AlgorithmAdjustmentPoint(
                    deliverAt: deliverAt,
                    isf: (row["insulinSensitivity"] as? NSDecimalNumber)?.decimalValue,
                    carbRatio: (row["carbRatio"] as? NSDecimalNumber)?.decimalValue,
                    autosensRatio: (row["sensitivityRatio"] as? NSDecimalNumber)?.decimalValue,
                    basalRate: (row["rate"] as? NSDecimalNumber)?.decimalValue
                )
            }
        }
    }
}
