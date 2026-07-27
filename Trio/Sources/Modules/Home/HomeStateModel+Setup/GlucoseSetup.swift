import CoreData
import Foundation

extension Home.StateModel {
    @MainActor func setupGlucoseController() {
        glucoseControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateGlucoseFromController()
            }
        }

        do {
            try glucoseController.performFetch()
            updateGlucoseFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform glucose fetch: \(error)")
        }

        previousDayGlucoseControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updatePreviousDayGlucoseFromController()
            }
        }

        do {
            try previousDayGlucoseController.performFetch()
            updatePreviousDayGlucoseFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform previous day glucose fetch: \(error)")
        }
    }

    @MainActor func updateGlucoseFromController() {
        guard let objects = glucoseController.fetchedObjects else { return }
        glucoseFromPersistence = objects
        latestTwoGlucoseValues = Array(objects.suffix(2))
        updateGlucoseChartYAxis(glucoseValues: objects)
        reanchorPreviousDayGlucoseController()
    }

    // Populates (or clears) the dimmed "yesterday" comparison overlay on the main chart.
    // Mirrors LoopFollow's "Show Yesterday's BG" behavior. The controller always stays live
    // (like every other FetchedResultsController on this state model); only the published
    // array is gated on the toggle, so flipping it on/off never needs a fresh disk fetch.
    @MainActor func updatePreviousDayGlucoseFromController() {
        glucoseFromPersistenceYesterday = showPreviousDayGlucose ? (previousDayGlucoseController.fetchedObjects ?? []) : []
    }

    // NSFetchedResultsController predicates are frozen at creation time -- Date.twoDaysAgo /
    // Date.oneDayAgo are evaluated once, not kept continuously current. Without re-anchoring,
    // the 24-48h-ago window silently goes stale as the day progresses: the shifted overlay
    // stops gaining new points past whatever moment it was last refreshed, which shows up as
    // the line abruptly ending mid-chart. Re-anchoring here, on the same ~5 minute cadence as
    // today's own glucose refresh, keeps the window continuously current without needing the
    // user to toggle the setting off/on to force a re-fetch.
    @MainActor private func reanchorPreviousDayGlucoseController() {
        previousDayGlucoseController.fetchRequest.predicate = NSPredicate.glucosePreviousDay
        do {
            try previousDayGlucoseController.performFetch()
            updatePreviousDayGlucoseFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to reanchor previous day glucose fetch: \(error)")
        }
    }

    /// Called from `MainChartView` on `.onChange(of: units)` to recompute the glucose-derived chart state.
    func setupGlucoseArray() {
        Task { @MainActor in
            updateGlucoseFromController()
        }
    }
}

extension Home.StateModel {
    func addManualGlucose(_ amount: Decimal) {
        let glucose = units == .mmolL ? amount.asMgdL : amount
        glucoseStorage.addManualGlucose(glucose: Int(glucose))
    }

    /// Today's glucose range distribution for the stats banner.
    var todayGlucoseDistribution: GlucoseDailyDistributionStats {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let readings = glucoseFromPersistence
            .filter { ($0.date ?? .distantPast) >= startOfDay }
            .map { GlucoseReading(value: Int($0.glucose), date: $0.date ?? startOfDay) }
        // first render happens before service injection
        let timeInRangeType = settingsManager?.settings.timeInRangeType ?? .timeInTightRange
        return GlucoseDailyDistributionStats.compute(
            date: startOfDay,
            readings: readings,
            // fixed consensus TIR bound (StatStateModel.highLimit), not the user's
            // chart threshold, so the banner always matches the Stats screen
            highLimit: 180,
            timeInRangeType: timeInRangeType
        )
    }
}
