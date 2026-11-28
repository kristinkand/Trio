import SwiftUI

struct GlucoseTrendView: View {
    let state: WatchState
    let rotationDegrees: Double
    let isWatchStateDated: Bool

    /// The value shown is one the watch read from the sensor itself (its reader, or untethered mode),
    /// not the phone's.
    private var readingIsWatchOwn: Bool {
        state.currentGlucoseIsWatchOwn || state.newestReadingIsOwn
    }

    /// A reading the sensor marked unreliable, newer than the reliable one shown and fresh: greyed with a warning sign.
    private var unsureReading: (date: Date, mgdl: Int)? {
        guard let date = state.unsureGlucoseDate, let mgdl = state.unsureGlucoseMgdl,
              Date().timeIntervalSince(date) < 12 * 60
        else { return nil }
        let shown = state.glucoseValues.last?.date ?? .distantPast
        return date > shown ? (date, mgdl) : nil
    }

    private var showsGlucose: Bool {
        !isWatchStateDated || unsureReading != nil
    }

    private var glucoseText: String {
        if let unsureReading {
            return WatchPhoneSigns.shared.format(Double(unsureReading.mgdl))
        }
        return isWatchStateDated ? "--" : state.currentGlucose
    }

    private var glucoseColor: Color {
        if unsureReading != nil { return Color.orange }
        return isWatchStateDated ? Color.secondary : state.currentGlucoseColorString.toColor()
    }

    private var deltaText: String? {
        if unsureReading != nil { return nil }
        guard let delta = state.delta else { return nil }
        return isWatchStateDated ? "--" : delta
    }

    private var bottomText: String {
        if let unsureReading {
            let minutes = max(0, Int(Date().timeIntervalSince(unsureReading.date) / 60))
            return String(
                localized: "Not reliable · \(minutes) min",
                comment: "Shown under a glucose value the G7 itself marks unreliable (minutes since the reading)"
            )
        }
        // the sensor's own state, when it sends no glucose: the reason, not "stale"
        let host = WatchCGMHost.shared
        if let label = host.sensorStateText, !host.isLent,
           (state.glucoseValues.last.map { Date().timeIntervalSince($0.date) > 6 * 60 } ?? true)
        {
            return label
        }
        // the watch's reader's own reading, shown while the phone's is older
        if state.newestReadingIsOwn, !state.currentGlucoseIsWatchOwn, let last = state.glucoseValues.last {
            let minutes = max(0, Int(Date().timeIntervalSince(last.date) / 60))
            return String(
                localized: "Watch sensor · \(minutes) min",
                comment: "Shown under the glucose when the watch read it from the sensor itself (minutes since the reading)"
            )
        }
        return isWatchStateDated ?
            String(localized: "STALE DATA", comment: "Information displayed when watch app data outdated or stale.") :
            state.lastLoopTime ?? "--"
    }

    private var effectiveRotation: Double { rotationDegrees }

    /// Determines the status color based on the time elapsed since the last loop
    /// - Parameter timeString: The time string representing minutes since last loop (format: "X min")
    /// - Returns: A color indicating the status:
    ///   - Green: <= 5 minutes
    ///   - Yellow: 5-10 minutes
    ///   - Red: > 10 minutes or invalid time
    private func statusColor(for timeString: String?) -> Color {
        guard let timeString = timeString,
              timeString != "--",
              let minutes = timeString.split(separator: " ").first.flatMap({ Int($0) })
        else {
            return Color.secondary
        }

        guard !isWatchStateDated else {
            return Color.secondary
        }

        switch minutes {
        case ...5:
            return Color.loopGreen
        case 5 ... 10:
            return Color.loopYellow
        case 11...:
            return Color.loopRed
        default:
            return Color.secondary
        }
    }

    var circleSize: CGFloat {
        switch state.deviceType {
        case .watch40mm:
            return 82
        case .watch41mm,
             .watch42mm:
            return 86
        case .watch44mm:
            return 96
        case .unknown,
             .watch45mm:
            return 103
        case .watch49mm:
            return 105
        }
    }

    var lineWidth: CGFloat {
        switch state.deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm,
             .watch44mm:
            return 1
        case .unknown,
             .watch45mm:
            return 1.5
        case .watch49mm:
            return 1.5
        }
    }

    var shadowRadius: CGFloat {
        switch state.deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm:
            return 8
        case .watch44mm:
            return 9
        case .unknown,
             .watch45mm:
            return 12
        case .watch49mm:
            return 12
        }
    }

    var currentGlucoseFontSize: Font {
        switch state.deviceType {
        case .watch40mm,
             .watch41mm,
             .watch42mm,
             .watch44mm:
            return .title2
        case .unknown,
             .watch45mm:
            return .title
        case .watch49mm:
            return .title
        }
    }

    var minutesAgoFontSize: CGFloat {
        switch state.deviceType {
        case .watch40mm,
             .watch41mm:
            return 9
        case .unknown,
             .watch42mm,
             .watch44mm:
            return 10
        case .watch45mm:
            return 11
        case .watch49mm:
            return 10
        }
    }

    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .stroke(statusColor(for: state.lastLoopTime), lineWidth: lineWidth)
                    .frame(width: circleSize, height: circleSize)
                    .background(Circle().fill(Color.bgDarkBlue))
                    .shadow(color: statusColor(for: state.lastLoopTime), radius: shadowRadius)

                TrendShape(
                    isWatchStateDated: !showsGlucose,
                    rotationDegrees: effectiveRotation,
                    deviceType: state.deviceType
                )
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: effectiveRotation)
                .shadow(color: Color.black.opacity(0.5), radius: 5)

                VStack(alignment: .center) {
                    Text(glucoseText)
                        .fontWeight(.semibold)
                        .font(currentGlucoseFontSize)
                        .foregroundStyle(glucoseColor)

                    if let deltaText {
                        Text(deltaText)
                            .fontWeight(.semibold)
                            .font(.system(.caption))
                            .foregroundStyle(.secondary)
                    }

                    // a value the sensor marks unreliable: an orange warning sign with it
                    if unsureReading != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Not reliable: the sensor reports an issue")
                    } else if WatchCGMHost.shared.hasSensorProblem, !WatchCGMHost.shared.isLent {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Sensor problem: see the sensor page")
                    } else if showsGlucose {
                        Image(systemName: readingIsWatchOwn ? "applewatch" : "iphone")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(readingIsWatchOwn ? "Reading from the watch" : "Reading from the iPhone")
                    }
                }
            }

            Spacer()

            Text(bottomText)
                .font(.system(size: minutesAgoFontSize))
                .fontWidth(isWatchStateDated ? .expanded : .standard)
                // "Not reliable · N min" in the warning sign's orange, so it reads as part of the warning
                .foregroundStyle(unsureReading != nil ? Color.orange : Color.primary)

            Spacer()

        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
