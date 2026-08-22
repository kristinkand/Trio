import CoreData
import Foundation

/// A single detected "food impact" event: the BG excursion following one real (non-FPU)
/// carb entry, from prebolus through peak through flattening back out.
///
/// Purely a read-only, display-only reconstruction of data the app already stored
/// (`CarbEntryStored`, `BolusStored`, `GlucoseStored`, `PumpEventStored`). Nothing here calls
/// into or changes the dosing algorithm, pump, or sensor code -- it only reads what's already
/// there and organizes it into a per-meal view.
struct MealImpactEvent: Identifiable {
    let id: UUID
    /// The triggering carb entry's own date/time.
    let mealDate: Date
    /// Nearest bolus delivered shortly before the meal, if one was found -- see
    /// `prebolusLookback`/`prebolusLookahead` below for what counts as "before".
    let prebolusDate: Date?
    let prebolusAmount: Double?
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
    /// First point after the peak where the curve has flattened out (or the last available
    /// reading in-window, if it never fully flattens before the window closes).
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
    /// window and prebolus lookback), then reduces them to one `MealImpactEvent` per
    /// non-FPU carb entry.
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
            // peak/flatten search below.
            let glucosePoints: [(date: Date, value: Double)] = glucoseReadings.compactMap {
                guard let date = $0.date else { return nil }
                return (date, Double($0.glucose))
            }
            let bolusPoints: [(date: Date, amount: Double)] = boluses.compactMap {
                guard let date = $0.pumpEvent?.timestamp, let amount = $0.amount?.doubleValue else { return nil }
                return (date, amount)
            }

            return carbEntries
                .compactMap { entry -> MealImpactEvent? in
                    guard let mealDate = entry.date else { return nil }
                    return buildMealImpactEvent(
                        id: entry.id ?? UUID(),
                        mealDate: mealDate,
                        carbs: entry.carbs,
                        fat: entry.fat,
                        protein: entry.protein,
                        glucosePoints: glucosePoints,
                        bolusPoints: bolusPoints
                    )
                }
                .sorted { $0.mealDate > $1.mealDate }
        }
    }
}

// MARK: - Detection algorithm (pure functions -- no Core Data access, no dosing side effects)

/// How far before a meal a bolus still counts as its "prebolus". The user's own cadence is
/// ~15 min before eating; this gives a little slack on both sides of that.
private let prebolusLookback = TimeInterval(minutes: 30)
private let prebolusLookahead = TimeInterval(minutes: 5)
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
/// A stretch this long where BG barely moves counts as "flattened out".
private let flatteningWindow = TimeInterval(minutes: 20)
private let flatteningThreshold: Double = 8

private func buildMealImpactEvent(
    id: UUID,
    mealDate: Date,
    carbs: Double,
    fat: Double,
    protein: Double,
    glucosePoints: [(date: Date, value: Double)],
    bolusPoints: [(date: Date, amount: Double)]
) -> MealImpactEvent {
    // 1. Prebolus: the closest bolus landing in [mealDate - 30min, mealDate + 5min].
    let prebolus = bolusPoints
        .filter {
            $0.date >= mealDate.addingTimeInterval(-prebolusLookback) &&
                $0.date <= mealDate.addingTimeInterval(prebolusLookahead)
        }
        .min { abs($0.date.timeIntervalSince(mealDate)) < abs($1.date.timeIntervalSince(mealDate)) }

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

    // 3. Flattening point: the first point strictly after the peak where BG barely moves
    // over the following ~20 min. Falls back to the last in-window reading if it never
    // flattens before the window closes.
    let afterPeak = glucosePoints.filter { $0.date > confirmedPeak.date && $0.date <= windowEnd }
    var end = afterPeak.last
    for point in afterPeak {
        let nearTerm = afterPeak.filter {
            $0.date >= point.date && $0.date <= point.date.addingTimeInterval(flatteningWindow)
        }
        guard nearTerm.count >= 2 else { continue }
        let spread = (nearTerm.map(\.value).max() ?? 0) - (nearTerm.map(\.value).min() ?? 0)
        if spread <= flatteningThreshold {
            end = point
            break
        }
    }

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

private func totalInsulin(
    in points: [(date: Date, amount: Double)],
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
