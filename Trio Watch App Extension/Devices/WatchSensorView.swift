import SwiftUI

/// The watch reading the sensor itself (`WatchCGMHost`): the newest reading, the link's state and how many of the
/// last hour's readings came, to compare with the phone's.
struct WatchSensorView: View {
    let state: WatchState
    @State private var now = Date()
    private static let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var host: WatchCGMHost { WatchCGMHost.shared }
    private var readings: [BloodGlucose] { state.ownReadings(since: now.addingTimeInterval(-60 * 60)) }
    /// Readings that came on time, as G7Direct counted them: one filled in after a gap doesn't count.
    private var onTime: Int { host.liveReadingDates.filter { $0 > now.addingTimeInterval(-60 * 60) }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("Watch Sensor", comment: "Title of the watch's own sensor page").font(.headline)
                if host.isLent {
                    note(String(localized: "Watch mode is reading the sensor. Its values are on the first pages."))
                } else if !host.isReadingDirectly {
                    note(String(localized: "No sensor from the iPhone yet: open Trio on the iPhone nearby."))
                } else {
                    if let latest = readings.last, let value = latest.glucose ?? latest.sgv {
                        Text(WatchPhoneSigns.shared.format(Double(value)) + " " + WatchPhoneSigns.shared.units)
                            .font(.title3).bold()
                        Text(
                            "\(max(0, Int(now.timeIntervalSince(latest.dateString) / 60))) min ago",
                            comment: "Age of the watch's own newest reading"
                        )
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    let status = host.sensorStateText ?? (host.isTalkingToSensor
                        ? String(localized: "Connected to the sensor")
                        : String(localized: "Waiting for the sensor's next reading"))
                    note(status, color: host.sensorHasEnded ? .red : host.hasSensorProblem ? .yellow : .secondary)
                    if let warmup = host.warmupEndsAt, warmup > now {
                        note(String(localized: "Warmup ends in \(Int(warmup.timeIntervalSince(now) / 60) + 1) min"))
                    }
                    // a reading every 5 minutes: 12 an hour
                    note(String(localized: "Last hour: \(onTime) of 12 readings on time"))
                }
            }
            .padding(.horizontal, 4)
        }
        .onReceive(Self.ticker) { now = $0 }
        .onAppear {
            now = Date()
            host.recheckAcquisition()
        }
    }

    private func note(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
    }
}
