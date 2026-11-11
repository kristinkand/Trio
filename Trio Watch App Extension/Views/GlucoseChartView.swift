import Charts
import Foundation
import SwiftUI
import WatchKit

/// IOB and COB at one loop, for the scrub line (as the phone's chart shows them).
struct WatchIobCobPoint {
    let date: Date
    let iob: Double
    let cob: Double
}

struct WatchTreatmentMarker: Identifiable {
    enum Kind { case bolus, smb, carbs }
    let id: String
    let date: Date
    let kind: Kind
}

/// As on the phone's main chart: a blue triangle above the reading for insulin, an orange dot below it for carbs.
struct TreatmentMarks: ChartContent {
    let markers: [WatchTreatmentMarker]
    let glucose: [(date: Date, glucose: Double, color: Color)]

    private struct Placed: Identifiable {
        let marker: WatchTreatmentMarker
        let y: Double
        var id: String { marker.id }
    }

    var body: some ChartContent {
        ForEach(placed) { placed in
            PointMark(x: .value("Time", placed.marker.date), y: .value("Glucose", placed.y))
                .symbol {
                    switch placed.marker.kind {
                    case .bolus,
                         .smb:
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: placed.marker.kind == .smb ? 6 : 9))
                            .foregroundStyle(Color.insulin)
                            .offset(y: -8)
                    case .carbs:
                        Circle().fill(Color.orange).frame(width: 7, height: 7).offset(y: 8)
                    }
                }
        }
    }

    /// Each marker on the reading nearest to it; none without a reading within 15 minutes.
    private var placed: [Placed] {
        guard let start = glucose.first?.date else { return [] }
        return markers.filter { $0.date >= start }.compactMap { marker -> Placed? in
            func gap(_ reading: (date: Date, glucose: Double, color: Color)) -> TimeInterval {
                abs(reading.date.timeIntervalSince(marker.date))
            }
            guard let nearest = glucose.min(by: { gap($0) < gap($1) }), gap(nearest) <= 15 * 60 else { return nil }
            return Placed(marker: marker, y: nearest.glucose)
        }
    }
}

struct GlucoseChartView: View {
    let state: WatchState
    let glucoseValues: [(date: Date, glucose: Double, color: Color)]

    @State private var timeWindow: TimeWindow = .oneHour
    /// Scrubbing back in time with the Digital Crown, in five-minute steps; tap the chart to start and to stop.
    /// As LoopFollow's watch app does it (nightscout/LoopFollow PR 785, AGPL-3.0).
    /// Owned by the main view, which owns the crown: one crown binding that scrubs here and turns pages
    /// otherwise, so nothing has to hand the crown back after scrubbing.
    @Binding var isScrubbing: Bool
    @Binding var scrubSteps: Double
    /// The chart takes the crown by focus while scrubbing (the vertical pages take it otherwise, by themselves)
    /// and gives it back when scrubbing ends.
    @FocusState private var crownFocused: Bool

    private var scrubOffset: TimeInterval { isScrubbing ? max(0, scrubSteps) * 300 : 0 }

    /// Back to the oldest reading the phone sent (24 hours).
    static func maxScrubSteps(_ glucoseValues: [(date: Date, glucose: Double, color: Color)]) -> Double {
        guard let oldest = glucoseValues.first?.date else { return 1 }
        return max(1, (Date().timeIntervalSince(oldest) / 300).rounded(.down))
    }

    /// The time the scrub line points at: where "now" sits when not scrubbing.
    private var scrubDate: Date { Date().addingTimeInterval(-scrubOffset) }

    /// The phone's values in mg/dL, the chart's in the display units.
    private var displayFactor: Double { WatchG7Reader.shared.isMmol ? 0.0555 : 1 }
    private var lowLine: Double? { state.chartLowMgDL.map { $0 * displayFactor } }
    private var highLine: Double? { state.chartHighMgDL.map { $0 * displayFactor } }
    private var targetLine: Double? { state.chartTargetMgDL.map { $0 * displayFactor } }

    enum TimeWindow: Int {
        case oneHour = 1
        case threeHours = 3
        case sixHours = 6
        case twelveHours = 12
        case twentyFourHours = 24

        var next: TimeWindow {
            switch self {
            case .oneHour: return .threeHours
            case .threeHours: return .sixHours
            case .sixHours: return .twelveHours
            case .twelveHours: return .twentyFourHours
            case .twentyFourHours: return .oneHour
            }
        }
    }

    /// The forecast's part of the window. Without forecast points it took 2 h, which in the 1 h window put the window's
    /// start an hour ahead of now: "No glucose readings" until a long press changed the window (25 October, second
    /// user). Now nothing without points, and never more than 40 % of the window, so the readings always show.
    private var futureOffset: TimeInterval {
        guard state.showForecast else { return 0 }
        let now = Date()
        let forecastEnd = state.isForecastCone ? forecastConePoints.last?.date : forecastLinePoints.map(\.date).max()
        guard let forecastEnd else { return 0 }
        let window = Double(timeWindow.rawValue) * 3600
        return min(max(0, forecastEnd.timeIntervalSince(now)), window * 0.4)
    }

    private var pastOffset: TimeInterval {
        let totalWindowDuration = Double(timeWindow.rawValue) * 3600
        return -(totalWindowDuration - futureOffset)
    }

    private var xAxisDomain: ClosedRange<Date> {
        let now = Date().addingTimeInterval(-scrubOffset)
        let startDate = now.addingTimeInterval(pastOffset)
        let endDate = now.addingTimeInterval(futureOffset)
        return startDate ... max(now, endDate)
    }

    private var filteredValues: [(date: Date, glucose: Double, color: Color)] {
        let domain = xAxisDomain
        return glucoseValues.filter { domain.contains($0.date) }
    }

    /// The G7's unreliable readings in the window, in display units: hollow orange dots, never used.
    private var filteredUnsureValues: [(date: Date, glucose: Double)] {
        guard state.showsUnreliableG7 else { return [] }
        let domain = xAxisDomain
        return state.unsureGlucoseHistory
            .filter { domain.contains($0.date) }
            .map { (date: $0.date, glucose: Double($0.mgdl) * displayFactor) }
    }

    /// A hollow dot as wide as a filled one: symbolSize is an area.
    private var unsurePointDiameter: CGFloat { (glucosePointSize / .pi).squareRoot() * 2 }

    /// The reading nearest the scrub line, within half a reading's spacing either way.
    private var scrubReading: (date: Date, glucose: Double, color: Color)? {
        let marker = scrubDate
        guard let nearest = glucoseValues.min(by: {
            abs($0.date.timeIntervalSince(marker)) < abs($1.date.timeIntervalSince(marker))
        }) else { return nil }
        return abs(nearest.date.timeIntervalSince(marker)) <= 150 ? nearest : nil
    }

    /// IOB and COB of the loop nearest the scrub line, within 2.5 minutes either way, as the phone's chart finds them.
    private var scrubIobCob: WatchIobCobPoint? {
        let marker = scrubDate
        let points = state.phoneIobCob + state.ownIobCob
        guard let nearest = points.min(by: {
            abs($0.date.timeIntervalSince(marker)) < abs($1.date.timeIntervalSince(marker))
        }) else { return nil }
        return abs(nearest.date.timeIntervalSince(marker)) <= 150 ? nearest : nil
    }

    struct ForecastConePoint: Identifiable {
        var id: Date { date }
        var date: Date
        var min: Double
        var max: Double
    }

    struct ForecastLinePoint: Identifiable {
        var id: String { "\(type)-\(date.timeIntervalSince1970)" }
        var type: String
        var date: Date
        var value: Double
    }

    private var forecastConePoints: [ForecastConePoint] {
        guard state.showForecast, state.isForecastCone, let anchorDate = state.forecastStartDate else { return [] }

        let minForecast = state.forecastConeMin
        let maxForecast = state.forecastConeMax
        let count = min(minForecast.count, maxForecast.count)

        var pts: [ForecastConePoint] = []
        for i in 0 ..< count {
            let date = anchorDate.addingTimeInterval(TimeInterval(i * 300))
            let yMin = minForecast[i]
            let yMax = maxForecast[i]

            if yMin == yMax {
                pts.append(ForecastConePoint(date: date, min: yMin - 1, max: yMax + 1))
            } else {
                pts.append(ForecastConePoint(date: date, min: yMin, max: yMax))
            }
        }
        return pts
    }

    private var forecastLinePoints: [ForecastLinePoint] {
        guard state.showForecast, !state.isForecastCone, let anchorDate = state.forecastStartDate else { return [] }

        var pts: [ForecastLinePoint] = []
        for (type, values) in state.forecastLines {
            for i in 0 ..< values.count {
                let date = anchorDate.addingTimeInterval(TimeInterval(i * 300))
                pts.append(ForecastLinePoint(type: type, date: date, value: values[i]))
            }
        }
        return pts
    }

    // MARK: - Adjustment bars

    /// The profile's runs as its bar shows them: the phone's, and while the watch holds the pod the one it loops on.
    private var profileRuns: [WatchAdjustmentRun] {
        let untethered = UntetheredWatchManager.shared
        guard untethered.isActive else { return state.profileRuns }
        let now = Date()
        // the phone's runs up to the session; the running one is the watch's own copy (it may have ended since)
        var runs = state.profileRuns.filter { $0.end.map { $0 <= now } ?? false }
        if let profile = untethered.data.grant?.profile {
            let phoneStart = state.profileRuns.last { $0.name == profile.name && $0.contains(now) }?.start
            // from a phone build without the start: the phone's own run, else the session's start (its epoch)
            let start = profile.startedAt ?? phoneStart
                ?? Date(timeIntervalSince1970: TimeInterval(untethered.data.session.epoch))
            runs.removeAll { $0.start == start }
            runs.append(WatchAdjustmentRun(name: profile.name, start: start, end: profile.endsAt))
        }
        return runs
    }

    /// Overrides as their bar shows them: the phone's, and while the watch holds the pod the one running there.
    private var overrideRuns: [WatchAdjustmentRun] {
        let untethered = UntetheredWatchManager.shared
        guard untethered.isActive else { return state.overrideRuns }
        let now = Date()
        var runs = state.overrideRuns.filter { $0.end.map { $0 <= now } ?? false }
        if let override = untethered.activeOverride(at: now) {
            let end = override.indefinite ? nil : override.date.addingTimeInterval(Double(truncating: override.duration as NSNumber) * 60)
            runs.removeAll { $0.start == override.date }
            runs.append(WatchAdjustmentRun(name: override.name, start: override.date, end: end))
        }
        return runs
    }

    /// Temp targets as their bar shows them: the phone's, and while the watch holds the pod the one running there.
    private var tempTargetRuns: [WatchAdjustmentRun] {
        let untethered = UntetheredWatchManager.shared
        guard untethered.isActive else { return state.tempTargetRuns }
        let now = Date()
        var runs = state.tempTargetRuns.filter { $0.end.map { $0 <= now } ?? false }
        if let tempTarget = untethered.activeTempTarget(at: now) {
            let end = tempTarget.createdAt.addingTimeInterval(Double(truncating: tempTarget.duration as NSNumber) * 60)
            runs.removeAll { $0.start == tempTarget.createdAt }
            runs.append(WatchAdjustmentRun(name: tempTarget.displayName, start: tempTarget.createdAt, end: end))
        }
        return runs
    }

    /// An override or temp target runs at that time: the loop leaves the profile aside then.
    private func profileSteppedAside(at date: Date) -> Bool {
        (overrideRuns + tempTargetRuns).contains { $0.contains(date) }
    }

    private enum BarKind: Int {
        case profile, override, tempTarget

        /// As on the phone's chart: the profile mint, overrides purple, temp targets green.
        var color: Color {
            switch self {
            case .profile: return .mint
            case .override: return .purple
            case .tempTarget: return .green
            }
        }
    }

    private struct Bar: Identifiable {
        let kind: BarKind
        let start: Date
        let end: Date
        /// Faded: an ended run, or the profile while an override or temp target leaves it aside.
        let faded: Bool
        var id: String { "\(kind.rawValue)-\(start.timeIntervalSince1970)-\(faded)" }
    }

    /// The runs within the window, cut to it; one without an end reaches the window's right edge. The profile's are
    /// split where an override or temp target runs, and those stretches faded.
    private var bars: [Bar] {
        let domain = xAxisDomain
        let now = Date()
        func clipped(_ run: WatchAdjustmentRun) -> (Date, Date)? {
            let start = max(run.start, domain.lowerBound)
            let end = min(run.end ?? domain.upperBound, domain.upperBound)
            return start < end ? (start, end) : nil
        }
        var bars: [Bar] = []
        let asides = (overrideRuns + tempTargetRuns).compactMap(clipped)
        for run in profileRuns {
            guard let range = clipped(run) else { continue }
            let (start, end) = range
            let ended = run.end.map { $0 <= now } ?? false
            // cut points: where an override or temp target starts or ends inside the run
            let cuts = ([start, end] + asides.flatMap { [$0.0, $0.1] }.filter { $0 > start && $0 < end }).sorted()
            for (from, to) in zip(cuts, cuts.dropFirst()) where from < to {
                let middle = from.addingTimeInterval(to.timeIntervalSince(from) / 2)
                bars.append(Bar(kind: .profile, start: from, end: to, faded: ended || profileSteppedAside(at: middle)))
            }
        }
        for (kind, runs) in [(BarKind.override, overrideRuns), (.tempTarget, tempTargetRuns)] {
            for run in runs {
                guard let range = clipped(run) else { continue }
                bars.append(Bar(kind: kind, start: range.0, end: range.1, faded: !run.contains(now)))
            }
        }
        return bars
    }

    /// The bars stack from the bottom, profile first, one lane for each kind in the window.
    private var barLanes: [BarKind] {
        Set(bars.map(\.kind)).sorted { $0.rawValue < $1.rawValue }
    }

    /// About 6 % of the graph's height per lane, in its units, with a small gap between lanes.
    private var barHeight: Double { (yAxisDomain.upperBound - yAxisDomain.lowerBound) * 0.06 }

    private func barBottom(_ kind: BarKind) -> Double {
        let lane = Double(barLanes.firstIndex(of: kind) ?? 0)
        return yAxisDomain.lowerBound + lane * barHeight * 1.2
    }

    private struct ScrubAdjustment: Identifiable {
        let kind: BarKind
        let run: WatchAdjustmentRun
        var id: Int { kind.rawValue }
    }

    /// The profile, override and temp target at the scrub line, for the scrub box.
    private var scrubAdjustments: [ScrubAdjustment] {
        let date = scrubDate
        let all: [(BarKind, [WatchAdjustmentRun])] = [(.profile, profileRuns), (.override, overrideRuns), (.tempTarget, tempTargetRuns)]
        return all.compactMap { entry in
            entry.1.last { $0.contains(date) }.map { ScrubAdjustment(kind: entry.0, run: $0) }
        }
    }

    var glucosePointSize: CGFloat {
        switch timeWindow {
        case .oneHour: return 24
        case .threeHours: return 18
        case .sixHours: return 14
        case .twelveHours: return 10
        case .twentyFourHours: return 6
        }
    }

    private var yAxisBounds: (min: Double, max: Double)? {
        let values = filteredValues.map(\.glucose) +
            filteredUnsureValues.map(\.glucose) +
            forecastConePoints.flatMap { [$0.min, $0.max] } +
            forecastLinePoints.map(\.value) +
            [lowLine, highLine].compactMap { $0 }

        guard let minValue = values.min(),
              let maxValue = values.max()
        else {
            return nil
        }
        return (minValue, maxValue)
    }

    private var yAxisDomain: ClosedRange<Double> {
        guard let bounds = yAxisBounds else { return 0 ... 1 }
        // as on the watch face: 0.5 mmol/L or 10 mg/dL past the readings and lines; the fixed 10 was mg/dL
        // only, and in mmol/L left the readings squeezed into a band in the middle
        let padding = WatchG7Reader.shared.isMmol ? 0.5 : 10
        return (bounds.min - padding) ... (bounds.max + padding)
    }

    private var yAxisValues: [Double] {
        guard let bounds = yAxisBounds else { return [] }
        guard bounds.min != bounds.max else { return [bounds.min] }
        let middle = roundedUpMiddle(for: bounds)
        return [bounds.min, middle, bounds.max].reduce(into: [Double]()) { values, value in
            guard !values.contains(where: { abs($0 - value) < 0.0001 }) else { return }
            values.append(value)
        }
    }

    private func roundedUpMiddle(for bounds: (min: Double, max: Double)) -> Double {
        let step = bounds.max < 40 ? 0.1 : 1
        let middle = (bounds.min + bounds.max) / 2
        return ceil(middle / step) * step
    }

    private func formattedYAxisLabel(for glucose: Double) -> String {
        glucose < 40 ? String(format: "%.1f", glucose) : "\(Int(glucose))"
    }

    var body: some View {
        VStack(spacing: 0) {
            if filteredValues.isEmpty, filteredUnsureValues.isEmpty {
                Text("No glucose readings.").font(.headline)
                Text("Check phone and CGM connectivity.").font(.caption)
            } else {
                Chart {
                    // the low and high thresholds dashed, the target solid, as on the watch face
                    if let lowLine {
                        RuleMark(y: .value("Low", lowLine))
                            .foregroundStyle(Color.red.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    if let highLine {
                        RuleMark(y: .value("High", highLine))
                            .foregroundStyle(Color.yellow.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                    if let targetLine {
                        RuleMark(y: .value("Target", targetLine))
                            .foregroundStyle(Color.loopGreen.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }

                    // the profile, overrides and temp targets: thin bars along the bottom, as on the phone's chart
                    ForEach(bars) { bar in
                        RectangleMark(
                            xStart: .value("Start", bar.start),
                            xEnd: .value("End", bar.end),
                            yStart: .value("Bottom", barBottom(bar.kind)),
                            yEnd: .value("Top", barBottom(bar.kind) + barHeight)
                        )
                        .foregroundStyle(bar.kind.color.opacity(bar.faded ? 0.35 : 1))
                    }

                    if isScrubbing {
                        RuleMark(x: .value("Scrub", scrubDate))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }

                    ForEach(filteredValues, id: \.date) { reading in
                        PointMark(
                            x: .value("Time", reading.date),
                            y: .value("Glucose", reading.glucose)
                        )
                        .foregroundStyle(reading.color)
                        .symbolSize(glucosePointSize)
                    }

                    ForEach(filteredUnsureValues, id: \.date) { reading in
                        PointMark(
                            x: .value("Time", reading.date),
                            y: .value("Glucose", reading.glucose)
                        )
                        .symbol {
                            Circle()
                                .strokeBorder(Color.orange, lineWidth: 1)
                                .frame(width: unsurePointDiameter, height: unsurePointDiameter)
                        }
                    }

                    // untethered mode's own history while it runs, else the phone's
                    TreatmentMarks(
                        markers: state.treatmentMarkers.isEmpty ? state.phoneTreatmentMarkers : state.treatmentMarkers,
                        glucose: filteredValues
                    )

                    if state.showForecast {
                        if state.isForecastCone {
                            ForEach(forecastConePoints) { pt in
                                AreaMark(
                                    x: .value("Time", pt.date),
                                    yStart: .value("Min", pt.min),
                                    yEnd: .value("Max", pt.max)
                                )
                                .foregroundStyle(Color.insulin.opacity(0.3))
                            }
                        } else {
                            ForEach(forecastLinePoints) { pt in
                                LineMark(
                                    x: .value("Time", pt.date),
                                    y: .value("Value", pt.value),
                                    series: .value("Type", pt.type)
                                )
                                .foregroundStyle(by: .value("Type", pt.type))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                            }
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "iob": Color.insulin,
                    "zt": Color.ZT,
                    "cob": Color.loopYellow,
                    "uam": Color.UAM
                ])
                .chartLegend(.hidden)
                .chartXAxis(.hidden)
                .chartXScale(domain: xAxisDomain)
                .chartYAxisLabel(isScrubbing ? "" : "\(timeWindow.rawValue) h", alignment: .topLeading)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: yAxisValues) { value in
                        AxisGridLine(stroke: .init(lineWidth: 0.65, dash: [2, 3]))
                            .foregroundStyle(Color.white.opacity(0.25))

                        AxisValueLabel {
                            if let glucose = value.as(Double.self) {
                                Text(formattedYAxisLabel(for: glucose))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartYScale(domain: yAxisDomain)
                .chartPlotStyle { plotContent in
                    plotContent
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.clear)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if isScrubbing { scrubHeader }
                }
            }
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        // tap: scrub with the crown, tap again: back to now; a long press changes the time span
        .onLongPressGesture {
            withAnimation {
                timeWindow = timeWindow.next
            }
        }
        .onTapGesture {
            scrubSteps = 0
            isScrubbing.toggle()
        }
        .focusable(isScrubbing)
        .focused($crownFocused)
        .digitalCrownRotation(
            $scrubSteps,
            // one step below now ends scrubbing
            from: -1,
            through: Self.maxScrubSteps(glucoseValues),
            by: 1,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        // focus follows scrubbing both ways, also when the main view ends it (timeout, past now, page change)
        .onChange(of: isScrubbing) { _, scrubbing in
            if scrubbing {
                // once the chart is focusable, on the next pass
                DispatchQueue.main.async { crownFocused = true }
                WKInterfaceDevice.current().play(.click)
            } else {
                crownFocused = false
            }
        }
    }

    /// Time and glucose at the scrub line.
    private var scrubHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Label {
                    Text(scrubDate, style: .time)
                } icon: {
                    Image(systemName: "clock")
                }
                .foregroundStyle(.secondary)
                Spacer()
                Label {
                    if let reading = scrubReading {
                        Text(formattedGlucose(reading.glucose))
                    } else {
                        Text("–")
                    }
                } icon: {
                    Image(systemName: "drop.fill")
                }
                .foregroundStyle(scrubReading?.color ?? .secondary)
            }
            .font(Self.scrubFont)
            .labelStyle(CompactLabelStyle())
            // IOB and COB at that time, as on the phone's chart
            if let point = scrubIobCob {
                HStack {
                    Label {
                        Text(String(format: "%.2f U", point.iob))
                    } icon: {
                        Image(systemName: "syringe.fill")
                    }
                    .foregroundStyle(Color.insulin)
                    Spacer()
                    Label {
                        Text("\(Int(point.cob.rounded())) g")
                    } icon: {
                        Image(systemName: "fork.knife")
                    }
                    .foregroundStyle(Color.orange)
                }
                .font(Self.scrubFont)
                .labelStyle(CompactLabelStyle())
            }
            // the profile, override and temp target at that time, each in its color, and until when
            ForEach(scrubAdjustments) { item in
                HStack(spacing: 3) {
                    Text(item.run.name).lineLimit(1)
                    if item.kind == .profile, profileSteppedAside(at: scrubDate) {
                        Text("(paused)")
                    } else if let end = item.run.end {
                        Text("until")
                        Text(end, style: .time)
                    }
                }
                .font(Self.scrubFont)
                .foregroundStyle(item.kind.color)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.6)))
    }

    /// Both lines at the scrub line in one size, symbols and values alike, between the headline and the old small
    /// second line.
    private static let scrubFont = Font.system(size: 14, weight: .semibold, design: .rounded)

    /// Icon and value close together, so both fit beside each other on a small watch; the icon takes the value's size.
    private struct CompactLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 3) {
                configuration.icon
                configuration.title
            }
        }
    }

    private func formattedGlucose(_ glucose: Double) -> String {
        WatchG7Reader.shared.isMmol ? String(format: "%.1f", glucose) : "\(Int(glucose.rounded()))"
    }
}
