import SwiftUI

/// The watch's own sensor link in detail, with the sensor kit's log: from the watch mode page's Log button.
struct WatchSensorDetailsView: View {
    @State private var showLog = false

    private var host: WatchCGMHost { WatchCGMHost.shared }
    private var phone: WatchPhoneSigns { WatchPhoneSigns.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                // to Messages or Mail, for whoever helps with testing
                ShareLink(
                    item: shareText,
                    subject: Text("Trio watch sensor log"),
                    preview: SharePreview("Trio watch sensor log")
                ) {
                    Label("Share log", systemImage: "square.and.arrow.up").font(.footnote)
                }

                VStack(alignment: .leading, spacing: 2) {
                    row(String(localized: "Sensor"), host.sensorID ?? "–")
                    row(
                        String(localized: "Link"),
                        host.isLent ? String(localized: "watch mode") : host.isTalkingToSensor ? "✓" : "–"
                    )
                    let coverage = host.recentCoverage
                    row(String(localized: "Last 2 h"), "\(coverage.count)/24 · max gap \(coverage.longestGapMinutes) min")
                    if let state = host.sensorStateText { row(String(localized: "State"), state) }
                    let watchReading = [
                        WatchState.shared.ownReadings(since: .distantPast).last?.dateString,
                        UntetheredWatchManager.shared.ownSessionReadingDate
                    ].compactMap { $0 }.max()
                    row(String(localized: "Watch BG"), watchReading.map(minutesAgo) ?? "–")
                    row(String(localized: "iPhone BG"), phone.phoneGlucoseDate.map(minutesAgo) ?? "–")
                    row(String(localized: "iPhone link"), phone.lastPhoneContact.map(minutesAgo) ?? "–")
                    row(String(localized: "Units"), phone.units)
                }
                .font(.caption2)

                if !host.logLines.isEmpty {
                    Divider()
                    Button {
                        withAnimation { showLog.toggle() }
                    } label: {
                        Label(
                            showLog ? String(localized: "Hide log") : String(localized: "Show log"),
                            systemImage: showLog ? "chevron.up" : "chevron.down"
                        )
                        .font(.footnote)
                    }
                    if showLog {
                        ForEach(Array(host.logLines.suffix(60).reversed().enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// The details above the log, then the whole log (up to 200 lines), oldest first.
    private var shareText: String {
        let coverage = host.recentCoverage
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
            + " (" + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?") + ")"
        let header = [
            "Trio watch sensor log, \(Date().formatted(date: .abbreviated, time: .shortened))",
            "Trio \(version)",
            "Sensor: \(host.sensorID ?? "–")",
            "Last 2 h: \(coverage.count)/24 readings on time, longest gap \(coverage.longestGapMinutes) min",
            "Units: \(phone.units)"
        ]
        return (header + [""] + host.logLines).joined(separator: "\n")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).lineLimit(1)
        }
    }

    private func minutesAgo(_ date: Date) -> String {
        String(localized: "\(max(0, Int(Date().timeIntervalSince(date) / 60))) min ago")
    }
}
