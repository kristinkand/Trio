import Charts
import CoreData
import Foundation
import SwiftUI

struct OverrideView: ChartContent {
    var state: Home.StateModel
    let overrides: [OverrideStored]
    let overrideRunStored: [OverrideRunStored]
    let units: GlucoseUnits
    let viewContext: NSManagedObjectContext

    var body: some ChartContent {
        drawActiveOverrides()
        drawOverrideRunStored()
    }

    private func drawActiveOverrides() -> some ChartContent {
        ForEach(overrides) { override in
            let start: Date = override.date ?? .distantPast
            let duration = MainChartHelper.calculateDuration(
                objectID: override.objectID,
                attribute: "duration",
                context: viewContext
            ) ?? 0
            let end: Date = {
                if override.indefinite {
                    return start.addingTimeInterval(60 * 60 * 24 * 30)
                } else if duration != 0 {
                    return start.addingTimeInterval(duration)
                } else {
                    return start.addingTimeInterval(60 * 60 * 24 * 30)
                }
            }()

            let target = getOverrideTarget(override: override)

            RuleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                y: .value("Value", units == .mgdL ? target : target.asMmolL)
            )
            .foregroundStyle(Color.purple.opacity(0.4))
            .lineStyle(.init(lineWidth: 8))
        }
    }

    private func drawOverrideRunStored() -> some ChartContent {
        ForEach(overrideRunStored) { overrideRunStored in
            let start: Date = overrideRunStored.startDate ?? .distantPast
            let end: Date = overrideRunStored.endDate ?? Date()
            let target = (overrideRunStored.target?.decimalValue ?? 100) == 0 ? 100 : overrideRunStored.target!.decimalValue
            RuleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                y: .value("Value", units == .mgdL ? target : target.asMmolL)
            )
            .foregroundStyle(Color.purple.opacity(0.25))
            .lineStyle(.init(lineWidth: 8))
        }
    }

    // Handle Overrides where no Target is provided
    private func getOverrideTarget(override: OverrideStored) -> Decimal {
        if let target = MainChartHelper
            .calculateTarget(objectID: override.objectID, attribute: "target", context: viewContext)
        {
            return target
        } else if override.target == 0 {
            return state.currentGlucoseTarget // Default target
        } else {
            return override.target?.decimalValue ?? state.currentGlucoseTarget
        }
    }
}

/// Mint band for Profile (see `WeekendProfileStore`), drawn exactly like an Override or Temp Target
/// band: at the Profile's target (or the normal target when it has none), stronger while running,
/// fainter for finished runs. Trio pauses Profile while a real Override or Temp Target runs, so
/// those stretches are left out and the band picks up again once they end.
struct WeekendProfileChartView: ChartContent {
    let state: Home.StateModel
    let units: GlucoseUnits
    let viewContext: NSManagedObjectContext

    private struct Piece: Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let isRunning: Bool
    }

    private static let farFuture: TimeInterval = 60 * 60 * 24 * 30

    var body: some ChartContent {
        let target = WeekendProfileStore.target != 0 ? WeekendProfileStore.target : state.currentGlucoseTarget
        let value = units == .mgdL ? target : target.asMmolL

        ForEach(pieces) { piece in
            RuleMark(
                xStart: .value("Start", piece.start, unit: .second),
                xEnd: .value("End", piece.end, unit: .second),
                y: .value("Value", value)
            )
            .foregroundStyle(Color.mint.opacity(piece.isRunning ? 0.4 : 0.25))
            .lineStyle(.init(lineWidth: 8))
        }
    }

    private var pieces: [Piece] {
        // Read so the chart redraws when Profile starts, stops or ends (it lives in
        // UserDefaults, which SwiftUI does not observe).
        _ = state.weekendProfileRevision

        let horizon = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        var runs: [(start: Date, end: Date, isRunning: Bool)] = WeekendProfileStore.runHistory
            .filter { $0.endDate > horizon }
            .map { (start: $0.startDate, end: $0.endDate, isRunning: false) }

        if WeekendProfileStore.isActive, let start = WeekendProfileStore.activeStartDate {
            let end = WeekendProfileStore.activeEndDate ?? start.addingTimeInterval(Self.farFuture)
            runs.append((start: start, end: end, isRunning: true))
        }

        let blockers = pausingIntervals
        var result: [Piece] = []
        for run in runs {
            var parts: [(start: Date, end: Date)] = [(start: run.start, end: run.end)]
            for blocker in blockers {
                parts = parts.flatMap { part -> [(start: Date, end: Date)] in
                    guard blocker.start < part.end, blocker.end > part.start else { return [part] }
                    var kept: [(start: Date, end: Date)] = []
                    if blocker.start > part.start { kept.append((start: part.start, end: blocker.start)) }
                    if blocker.end < part.end { kept.append((start: blocker.end, end: part.end)) }
                    return kept
                }
            }
            for part in parts where part.end > part.start {
                result.append(Piece(id: result.count, start: part.start, end: part.end, isRunning: run.isRunning))
            }
        }
        return result
    }

    /// Every Override and Temp Target stretch on the chart, finished or running.
    private var pausingIntervals: [(start: Date, end: Date)] {
        var list: [(start: Date, end: Date)] = []

        for run in state.overrideRunStored {
            if let start = run.startDate, let end = run.endDate { list.append((start: start, end: end)) }
        }
        for run in state.tempTargetRunStored {
            if let start = run.startDate, let end = run.endDate { list.append((start: start, end: end)) }
        }
        for override in state.overrides {
            let start = override.date ?? .distantPast
            let duration = MainChartHelper.calculateDuration(
                objectID: override.objectID,
                attribute: "duration",
                context: viewContext
            ) ?? 0
            let end = override.indefinite || duration == 0
                ? start.addingTimeInterval(Self.farFuture)
                : start.addingTimeInterval(duration)
            list.append((start: start, end: end))
        }
        for tempTarget in state.tempTargetStored {
            let start = tempTarget.date ?? .distantPast
            if let duration = MainChartHelper.calculateDuration(
                objectID: tempTarget.objectID,
                attribute: "duration",
                context: viewContext
            ) {
                list.append((start: start, end: start.addingTimeInterval(duration)))
            }
        }
        return list
    }
}
