import CoreData
import Foundation

/// One loop that carries Boost's line in its reason: the SMB the loop gave, and the SMB Boost would have given.
/// Read only from what `OrefDetermination` already stores; nothing here touches dosing.
struct BoostShadowPoint: Identifiable {
    var id: Date { date }
    let date: Date
    /// mg/dL
    let glucose: Decimal?
    let trioSMB: Decimal
    let boostSMB: Decimal
    /// Boost's meal stage: IDLE, OBSERVING, CONFIRMED, COMMITTED or RECOVERING.
    let state: String
    let asleep: Bool
}

/// A meal as Boost saw it: from the first loop that left IDLE until it was back in IDLE.
struct BoostMealEpisode: Identifiable {
    var id: Date { start }
    let start: Date
    let end: Date
    /// The furthest stage reached (COMMITTED beyond CONFIRMED beyond OBSERVING).
    let furthestState: String
    let trioSMB: Decimal
    let boostSMB: Decimal
    /// mg/dL
    let startGlucose: Decimal?
    let peakGlucose: Decimal?
    /// The lowest loop glucose from the start until 3 hours after the end, mg/dL.
    let lowestAfter: Decimal?
}

/// Per calendar day, for the longer spans.
struct BoostShadowDay: Identifiable {
    var id: Date { day }
    let day: Date
    let trioSMB: Decimal
    let boostSMB: Decimal
}

enum BoostShadowParser {
    private static let tag = try? NSRegularExpression(
        pattern: #"boostV5\[[a-z]+\]: state=([A-Z]+) score=[-0-9.]+ wouldSMB=([0-9.]+)U; ml\([^)]*\)([a-zA-Z ]*)"#
    )

    /// The stage, Boost's would-be SMB and whether it read asleep, from a determination's reason; nil without the line
    /// (Boost off, or a loop the watch ran in watch mode).
    static func parse(_ reason: String) -> (state: String, wouldSMB: Decimal, asleep: Bool)? {
        guard let tag,
              let match = tag.firstMatch(in: reason, range: NSRange(reason.startIndex..., in: reason)),
              let stateRange = Range(match.range(at: 1), in: reason),
              let smbRange = Range(match.range(at: 2), in: reason),
              let smb = Decimal(string: String(reason[smbRange]), locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        let context = Range(match.range(at: 3), in: reason).map { String(reason[$0]) } ?? ""
        return (String(reason[stateRange]), smb, context.split(separator: " ").contains("asleep"))
    }

    /// Meals: runs of loops away from IDLE.
    static func episodes(_ points: [BoostShadowPoint]) -> [BoostMealEpisode] {
        let rank = ["OBSERVING": 1, "RECOVERING": 1, "CONFIRMED": 2, "COMMITTED": 3]
        var episodes: [BoostMealEpisode] = []
        var run: [BoostShadowPoint] = []

        func close() {
            guard let first = run.first, let last = run.last else { return }
            let furthest = run.max { (rank[$0.state] ?? 0) < (rank[$1.state] ?? 0) }?.state ?? first.state
            let until = last.date.addingTimeInterval(3 * 3600)
            let after = points.filter { $0.date >= first.date && $0.date <= until }.compactMap(\.glucose)
            episodes.append(BoostMealEpisode(
                start: first.date,
                end: last.date,
                furthestState: furthest,
                trioSMB: run.reduce(0) { $0 + $1.trioSMB },
                boostSMB: run.reduce(0) { $0 + $1.boostSMB },
                startGlucose: first.glucose,
                peakGlucose: run.compactMap(\.glucose).max(),
                lowestAfter: after.min()
            ))
            run = []
        }

        for point in points {
            if point.state == "IDLE" { close() } else { run.append(point) }
        }
        close()
        // a stage that never got past OBSERVING is Boost watching, not a meal
        return Array(episodes.filter { $0.furthestState != "OBSERVING" && $0.furthestState != "RECOVERING" }.reversed())
    }

    static func days(_ points: [BoostShadowPoint]) -> [BoostShadowDay] {
        let calendar = Calendar.current
        return Dictionary(grouping: points) { calendar.startOfDay(for: $0.date) }
            .map { day, points in
                BoostShadowDay(
                    day: day,
                    trioSMB: points.reduce(0) { $0 + $1.trioSMB },
                    boostSMB: points.reduce(0) { $0 + $1.boostSMB }
                )
            }
            .sorted { $0.day < $1.day }
    }
}

extension Stat.StateModel {
    /// Fetches the loops of the selected span and keeps those with Boost's line, for the Boost tab.
    func setupBoostShadowStats() {
        Task {
            do {
                let points = try await fetchBoostShadowPoints(for: selectedIntervalForBoostStats)
                await MainActor.run {
                    self.boostShadowPoints = points.points
                    self.boostLoopsWithoutLine = points.withoutLine
                }
            } catch {
                debug(.storage, "\(DebuggingIdentifiers.failed) failed to fetch Boost shadow stats: \(error)")
            }
        }
    }

    func fetchBoostShadowPoints(
        for interval: StatsTimeIntervalWithToday
    ) async throws -> (points: [BoostShadowPoint], withoutLine: Int) {
        let taskContext = CoreDataStack.shared.newTaskContext()
        taskContext.name = "StatStateModel.fetchBoostShadowPoints"

        let now = Date()
        let startDate: Date
        switch interval {
        case .day: startDate = now.addingTimeInterval(-TimeInterval(hours: 24))
        case .today: startDate = Calendar.current.startOfDay(for: now)
        case .week: startDate = now.addingTimeInterval(-TimeInterval(hours: 24 * 7))
        case .month: startDate = now.addingTimeInterval(-TimeInterval(hours: 24 * 30))
        case .total: startDate = now.addingTimeInterval(-TimeInterval(hours: 24 * 90))
        }

        // as the Algorithm tab: whole objects, suggested-only loops included
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
            var withoutLine = 0
            let points = determinations.compactMap { determination -> BoostShadowPoint? in
                guard let date = determination.deliverAt else { return nil }
                guard let line = BoostShadowParser.parse(determination.reason ?? "") else {
                    withoutLine += 1
                    return nil
                }
                return BoostShadowPoint(
                    date: date,
                    glucose: determination.glucose?.decimalValue,
                    trioSMB: determination.smbToDeliver?.decimalValue ?? 0,
                    boostSMB: line.wouldSMB,
                    state: line.state,
                    asleep: line.asleep
                )
            }
            return (points, withoutLine)
        }
    }
}
