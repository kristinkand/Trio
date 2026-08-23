import CoreData
import Foundation

/// A single detected "food impact" event: the BG excursion following one real (non-FPU)
/// carb entry, from prebolus through peak through the end of the tracked window.
///
/// Purely a read-only, display-only reconstruction of data the app already stored
/// (`CarbEntryStored`, `BolusStored`, `GlucoseStored`, `PumpEventStored`). Nothing here calls
/// into or changes the dosing algorithm, pump, or sensor code -- it only reads what's already
/// there and organizes it into a per-meal view.
struct MealImpactEvent: Identifiable {
    let id: UUID
    /// The triggering carb entry's own date/time.
    let mealDate: Date
    /// The most recent bolus given meaningfully before the meal, if one was found -- see
    /// `prebolusLookback`/`prebolusMinGapBeforeMeal` below for what counts as "before".
    let prebolusDate: Date?
    let prebolusAmount: Double?
    /// Carbs/fat/protein for this event, INCLUDING any later bolus-free carb entries folded
    /// in as a continuation of this same meal -- see `groupMealTriggers` below.
    let carbs: Double
    let fat: Double
    let protein: Double
    /// Start of the tracked window: the prebolus time if one was found, else the meal time.
    let startDate: Date
    let startBG: Double?
    /// The GLOBAL maximum BG reached in the (possibly extended) window -- not simply the
    /// first local high point. A meal high in fat/protein can dip after an initial rise and
    /// then rise again later to a higher point; only the true maximum should count as "the
    /// peak", or a real delayed peak would get missed.
    let peakDate: Date?
    let peakBG: Double?
    /// The last glucose reading at or before the window's close. Deliberately NOT "wherever
    /// the curve first looks flat" -- an early plateau mid-digestion (common with high-fat/
    /// protein meals) would otherwise get mistaken for the end and cut the window short.
    /// Standard carb-ratio testing looks at the full ~4h+ window regardless of a mid-curve
    /// lull, so `endDate`/`endBG` always land at the true window boundary.
    let endDate: Date?
    let endBG: Double?
    /// Total bolus insulin -- prebolus + meal bolus + every SMB delivered between `startDate`
    /// and `endDate`. Deliberately excludes basal: oref doesn't tag basal as "for this meal"
    /// vs. background, so this only sums discrete bolus-type deliveries.
    let totalInsulin: Double
    /// True when the curve shows two distinct rises separated by a real dip -- e.g. a fast
    /// early rise from the carbs, a partial come-down, then a later second rise (often from a
    /// high-fat/protein meal's delayed absorption). Useful for spotting which meals do this.
    let hasSecondaryRise: Bool
    let secondaryRiseDate: Date?
    let secondaryRiseBG: Double?
}

extension Stat.StateModel {
    /// Kicks off fetching + processing of meal-impact events for the "Food Impact" stats tab.
    func setupMealImpactStats() {
        Task {
            do {
                let events = try await fetchMealImpactEvents(for: selectedIntervalForMealImpactStats)
                await MainActor.run {
                    self.mealImpactEvents = events
                }
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed to fetch meal impact stats: \(error)")
            }
        }
    }

    /// Fetches carb entries, glucose readings, and boluses covering the selected duration
    /// (padded on both edges so a meal near the edge still gets its full follow-through
    /// window and prebolus lookback), groups carb entries into one trigger per real meal
    /// (folding in any later bolus-free "more carbs coming" entries -- see
    /// `groupMealTriggers`), then reduces each trigger to one `MealImpactEvent`.
    func fetchMealImpactEvents(for interval: StatsTimeInterval) async throws -> [MealImpactEvent] {
        let taskContext = CoreDataStack.shared.newTaskContext()
        taskContext.name = "StatStateModel.fetchMealImpactEvents"

        let now = Date()
        let lookbackStart: Date
        switch interval {
        case .day:
            lookbackStart = now.addingTimeInterval(-TimeInterval(hours: 24))
        case .week:
            lookbackStart = now.addingTimeInterval(-TimeInterval(hours: 24 * 7))
        case .month:
            lookbackStart = now.addingTimeInterval(-TimeInterval(hours: 24 * 30))
        case .total:
            lookbackStart = now.addingTimeInterval(-TimeInterval(hours: 24 * 90))
        }

        // Real, user-entered carb entries only -- oref's own synthetic delayed-FPU follow-up
        // entries (`isFPU == true`) share the original meal's macros already and would
        // otherwise show up as phantom extra "meals" with no glucose rise of their own.
        let carbsPredicate = NSPredicate(
            format: "isFPU == %@ AND date >= %@ AND date <= %@ AND carbs > 0",
            false as NSNumber, lookbackStart as NSDate, now as NSDate
        )
        // Padded well past the requested range so meals near either edge still get their
        // full ~4-7h follow-through window and prebolus lookback in a single fetch.
        let fetchPadding = TimeInterval(hours: 8)
        let glucosePredicate = NSPredicate(
            format: "date >= %@ AND date <= %@",
            lookbackStart.addingTimeInterval(-fetchPadding) as NSDate,
            now.addingTimeInterval(fetchPadding) as NSDate
        )
        let bolusPredicate = NSPredicate(
            format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp <= %@",
            lookbackStart.addingTimeInterval(-fetchPadding) as NSDate,
            now.addingTimeInterval(fetchPadding) as NSDate
        )

        async let carbsResult = CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: taskContext,
            predicate: carbsPredicate,
            key: "date",
            ascending: true,
            batchSize: 100
        )
        async let glucoseResult = CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: taskContext,
            predicate: glucosePredicate,
            key: "date",
            ascending: true,
            batchSize: 200
        )
        async let bolusResult = CoreDataStack.shared.fetchEntitiesAsync(
            ofType: BolusStored.self,
            onContext: taskContext,
            predicate: bolusPredicate,
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 100
        )

        let (carbsAny, glucoseAny, bolusAny) = try await (carbsResult, glucoseResult, bolusResult)

        return try await taskContext.perform {
            guard let carbEntries = carbsAny as? [CarbEntryStored],
                  let glucoseReadings = glucoseAny as? [GlucoseStored],
                  let boluses = bolusAny as? [BolusStored]
            else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            // Reduced to plain (date, value) tuples up front -- easier to reason about (and
            // to unit test) than repeatedly faulting into managed objects during the
            // peak search below.
            let glucosePoints: [(date: Date, value: Double)] = glucoseReadings.compactMap {
                guard let date = $0.date else { return nil }
                return (date, Double($0.glucose))
            }
            let bolusPoints: [(date: Date, amount: Double, isSMB: Bool)] = boluses.compactMap {
                guard let date = $0.pumpEvent?.timestamp, let amount = $0.amount?.doubleValue else { return nil }
                return (date, amount, $0.isSMB)
            }
            let rawTriggers: [RawMealTrigger] = carbEntries.compactMap {
                guard let date = $0.date else { return nil }
                return RawMealTrigger(id: $0.id ?? UUID(), date: date, carbs: $0.carbs, fat: $0.fat, protein: $0.protein)
            }

            return groupMealTriggers(rawTriggers, bolusPoints: bolusPoints)
                .map { trigger in
                    buildMealImpactEvent(
                        id: trigger.id,
                        mealDate: trigger.date,
                        carbs: trigger.carbs,
                        fat: trigger.fat,
                        protein: trigger.protein,
                        glucosePoints: glucosePoints,
                        bolusPoints: bolusPoints
                    )
                }
                .sorted { $0.mealDate > $1.mealDate }
        }
    }
}

// MARK: - Detection algorithm (pure functions -- no Core Data access, no dosing side effects)

/// How far before a meal a bolus still counts as its "prebolus". A prebolus is typically
/// given 10-15 min before eating; 20 min gives a little slack above that.
private let prebolusLookback = TimeInterval(minutes: 20)
/// A bolus has to land at least this long before the carb entry to count as a genuine
/// prebolus. Without this, a bolus given at essentially the same moment as the carb entry
/// (e.g. a top-up dosed at the table, on top of an earlier real prebolus) would always win
/// under a plain "closest in time" comparison -- its time gap to the meal is ~0, which beats
/// any real prebolus given meaningfully earlier. Requiring a minimum gap excludes same-time
/// top-ups from candidacy entirely, so only boluses genuinely given *ahead* of the meal are
/// considered.
private let prebolusMinGapBeforeMeal = TimeInterval(minutes: 3)
/// How far either side of a LATER carb entry counts as "this entry got its own insulin
/// coverage". Used only for grouping (see `groupMealTriggers`) -- a carb entry with no bolus
/// anywhere near it is a "heads up, more carbs coming" annotation for an already-covered
/// meal, not a new, separately-dosed one.
private let followUpBolusWindow = TimeInterval(minutes: 20)
/// Base tracked window length -- the ~4h cycle the user described.
private let baseWindowLength = TimeInterval(hours: 4)
/// How far the window can be pushed out chasing a still-rising, delayed (fat/protein) peak.
private let maxWindowExtension = TimeInterval(hours: 3)
private let extensionStep = TimeInterval(hours: 1)
/// A running peak found within this many minutes of the window's current end is treated as
/// "possibly still rising", which triggers another extension check.
private let stillRisingMargin = TimeInterval(minutes: 30)
/// Minimum dip-to-peak rebound (mg/dL) for an earlier local high point to count as a genuine
/// secondary rise rather than sensor noise.
private let secondaryRiseProminence: Double = 15
/// Minimum time gap between an earlier local high point and the true peak for it to count as
/// its own separate rise rather than just the tail of the same one.
private let secondaryRiseMinSeparation = TimeInterval(minutes: 45)

/// One raw, ungrouped carb entry as read straight from Core Data.
private struct RawMealTrigger {
    let id: UUID
    let date: Date
    let carbs: Double
    let fat: Double
    let protein: Double
}

/// Groups raw carb entries into one trigger per real meal.
///
/// Some entries aren't a new meal at all: logging carbs with no bolus attached, sometime
/// after an already-covered meal, is a deliberate way to warn oref that a second, delayed
/// rise is coming (e.g. for a high-fat/protein meal) -- without actually dosing more
/// insulin for it. Left alone, every one of those would spawn its own phantom "meal" card
/// with no prebolus and its own separate (and misleading) impact window.
///
/// A later entry gets folded into the meal right before it -- its carbs/fat/protein added
/// on, no separate event created -- when BOTH hold:
///   - it falls within `baseWindowLength` of that meal's own start (still plausibly the same
///     digestion cycle), and
///   - it has no bolus of its own within `followUpBolusWindow` (i.e. it wasn't actually given
///     its own insulin coverage, which would make it a genuine second, separately-dosed meal).
/// Otherwise it starts a new group of its own.
private func groupMealTriggers(
    _ rawTriggers: [RawMealTrigger],
    bolusPoints: [(date: Date, amount: Double, isSMB: Bool)]
) -> [RawMealTrigger] {
    var groups: [RawMealTrigger] = []

    for entry in rawTriggers.sorted(by: { $0.date < $1.date }) {
        let hasOwnBolus = bolusPoints.contains {
            !$0.isSMB &&
                $0.date >= entry.date.addingTimeInterval(-followUpBolusWindow) &&
                $0.date <= entry.date.addingTimeInterval(followUpBolusWindow)
        }

        if !hasOwnBolus,
           let last = groups.last,
           entry.date <= last.date.addingTimeInterval(baseWindowLength)
        {
            // Fold into the meal already open -- same digestion cycle, just a heads-up that
            // more carbs are on the way, not a new, separately-dosed meal.
            groups[groups.count - 1] = RawMealTrigger(
                id: last.id,
                date: last.date,
                carbs: last.carbs + entry.carbs,
                fat: last.fat + entry.fat,
                protein: last.protein + entry.protein
            )
        } else {
            groups.append(entry)
        }
    }

    return groups
}

private func buildMealImpactEvent(
    id: UUID,
    mealDate: Date,
    carbs: Double,
    fat: Double,
    protein: Double,
    glucosePoints: [(date: Date, value: Double)],
    bolusPoints: [(date: Date, amount: Double, isSMB: Bool)]
) -> MealImpactEvent {
    // 1. Prebolus: the MOST RECENT qualifying bolus given at least `prebolusMinGapBeforeMeal`
    // before the meal, within `prebolusLookback` of it. Two exclusions matter here:
    //   - SMBs: automatic micro-boluses the closed loop fires on its own (often every ~5 min
    //     while correcting), not a deliberate prebolus action -- one can easily land in this
    //     window if BG happened to be elevated before the meal for an unrelated reason.
    //   - Anything within `prebolusMinGapBeforeMeal` of the carb entry: this is what a
    //     same-time "top-up" bolus (dosed right at the table, on top of an earlier real
    //     prebolus) looks like. Since all remaining candidates are now guaranteed to be
    //     before the meal by at least that gap, the one closest to the meal is simply the
    //     one with the latest (most recent) date.
    let prebolus = bolusPoints
        .filter {
            !$0.isSMB &&
                $0.date >= mealDate.addingTimeInterval(-prebolusLookback) &&
                $0.date <= mealDate.addingTimeInterval(-prebolusMinGapBeforeMeal)
        }
        .max { $0.date < $1.date }

    let startDate = min(prebolus?.date ?? mealDate, mealDate)
    let startBG = nearestGlucose(to: startDate, in: glucosePoints)?.value

    // 2. Extend the window while the running global-max peak still sits too close to the
    // current edge to trust it as final -- i.e. the curve may still be climbing.
    var windowEnd = startDate.addingTimeInterval(baseWindowLength)
    let hardCap = startDate.addingTimeInterval(baseWindowLength + maxWindowExtension)
    var peak = globalMax(in: glucosePoints, from: startDate, to: windowEnd)
    while let currentPeak = peak,
          windowEnd < hardCap,
          currentPeak.date >= windowEnd.addingTimeInterval(-stillRisingMargin)
    {
        windowEnd = min(windowEnd.addingTimeInterval(extensionStep), hardCap)
        peak = globalMax(in: glucosePoints, from: startDate, to: windowEnd)
    }

    guard let confirmedPeak = peak else {
        // No glucose data at all in-window -- still surface the meal/dosing facts, just
        // without a BG-derived peak/end.
        return MealImpactEvent(
            id: id, mealDate: mealDate, prebolusDate: prebolus?.date, prebolusAmount: prebolus?.amount,
            carbs: carbs, fat: fat, protein: protein, startDate: startDate, startBG: startBG,
            peakDate: nil, peakBG: nil, endDate: nil, endBG: nil,
            totalInsulin: totalInsulin(in: bolusPoints, from: startDate, to: windowEnd),
            hasSecondaryRise: false, secondaryRiseDate: nil, secondaryRiseBG: nil
        )
    }

    // 3. End of window: the last available glucose reading at or before `windowEnd`. This is
    // deliberately just the window boundary rather than an earlier "looks flattened out"
    // heuristic -- a brief mid-digestion plateau (common well before a meal is fully
    // absorbed) was getting mistaken for the end and cutting the tracked window short, well
    // under the full ~4h a carb-ratio test actually needs to see.
    let end = glucosePoints.last { $0.date > confirmedPeak.date && $0.date <= windowEnd }

    // 4. Secondary-rise flag: an earlier local high point, well before the true peak, with a
    // real dip in between -- i.e. genuinely a second rise, not just the leading edge of the
    // same one.
    let beforePeak = glucosePoints.filter { $0.date >= startDate && $0.date <= confirmedPeak.date }
    let secondary = localMaxima(in: beforePeak, minProminence: secondaryRiseProminence)
        .filter { confirmedPeak.date.timeIntervalSince($0.date) >= secondaryRiseMinSeparation }
        .max { $0.value < $1.value }

    return MealImpactEvent(
        id: id,
        mealDate: mealDate,
        prebolusDate: prebolus?.date,
        prebolusAmount: prebolus?.amount,
        carbs: carbs,
        fat: fat,
        protein: protein,
        startDate: startDate,
        startBG: startBG,
        peakDate: confirmedPeak.date,
        peakBG: confirmedPeak.value,
        endDate: end?.date,
        endBG: end?.value,
        totalInsulin: totalInsulin(in: bolusPoints, from: startDate, to: end?.date ?? windowEnd),
        hasSecondaryRise: secondary != nil,
        secondaryRiseDate: secondary?.date,
        secondaryRiseBG: secondary?.value
    )
}

private func nearestGlucose(
    to date: Date,
    in points: [(date: Date, value: Double)]
) -> (date: Date, value: Double)? {
    points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
}

private func globalMax(
    in points: [(date: Date, value: Double)],
    from start: Date,
    to end: Date
) -> (date: Date, value: Double)? {
    points.filter { $0.date >= start && $0.date <= end }.max { $0.value < $1.value }
}

/// Sums ALL boluses in the window -- prebolus, meal bolus, and every SMB -- regardless of
/// isSMB. Unlike prebolus identification (which deliberately excludes SMBs), "total insulin
/// used" is meant to capture every drop of bolus-type insulin delivered during the meal's
/// impact window, exactly as SMBs are still real insulin the algorithm gave in response to
/// this meal.
private func totalInsulin(
    in points: [(date: Date, amount: Double, isSMB: Bool)],
    from start: Date,
    to end: Date
) -> Double {
    points.filter { $0.date >= start && $0.date <= end }.reduce(0) { $0 + $1.amount }
}

/// Finds local maxima in time order: a point at least as high as both its immediate
/// neighbors, standing at least `minProminence` mg/dL above the nearest dip on whichever
/// side is shallower (so a single noisy sample next to it can't manufacture a fake maximum).
private func localMaxima(
    in points: [(date: Date, value: Double)],
    minProminence: Double
) -> [(date: Date, value: Double)] {
    guard points.count >= 3 else { return [] }
    var maxima: [(date: Date, value: Double)] = []

    for i in 1 ..< (points.count - 1) {
        let prev = points[i - 1]
        let cur = points[i]
        let next = points[i + 1]
        guard cur.value >= prev.value, cur.value >= next.value else { continue }

        var leftMin = cur.value
        var j = i - 1
        while j >= 0, points[j].value <= cur.value {
            leftMin = min(leftMin, points[j].value)
            j -= 1
        }
        var rightMin = cur.value
        var k = i + 1
        while k < points.count, points[k].value <= cur.value {
            rightMin = min(rightMin, points[k].value)
            k += 1
        }

        let prominence = cur.value - max(leftMin, rightMin)
        if prominence >= minProminence {
            maxima.append(cur)
        }
    }
    return maxima
}
