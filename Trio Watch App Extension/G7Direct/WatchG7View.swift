import SwiftUI

/// The watch's own G7 reading: the switch, what the watch is doing, its latest
/// readings, and a short log for testing.
struct WatchG7View: View {
    @State private var showResetConfirmation = false

    private var reader: WatchG7Reader { WatchG7Reader.shared }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { reader.isEnabled },
                    set: { reader.setEnabled($0) }
                )) {
                    Text("Read sensor on watch", comment: "Toggle: the watch connects to the G7 itself")
                        .font(.footnote)
                }

                Text(reader.statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if reader.isEnabled, !reader.hasWatchKey, reader.sensorName != nil {
                    Text(
                        "First time: keep the iPhone nearby and this page open. If the watch asks to pair with the sensor, accept.",
                        comment: "Watch G7 page: hint while the watch has not paired with the sensor yet"
                    )
                    .font(.caption2)
                    .foregroundStyle(Color.loopYellow)
                    .fixedSize(horizontal: false, vertical: true)
                }

                if reader.isEnabled {
                    latestSection
                    detailsSection
                    if !reader.logLines.isEmpty {
                        logSection
                    }
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Text("Pair watch again", comment: "Button: forget the watch's own pairing with the sensor")
                            .font(.footnote)
                    }
                    .disabled(!reader.hasWatchKey)
                } else {
                    Text(
                        "With this on, the watch reads your G7 itself in its own slot, so glucose and low/high alerts keep working when the iPhone is out of reach. It does not loop or dose.",
                        comment: "Explanation under the watch G7 toggle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 4)
        }
        .confirmationDialog(
            Text("Pair the watch with the sensor again?", comment: "Confirmation title for resetting the watch's sensor pairing"),
            isPresented: $showResetConfirmation
        ) {
            Button(role: .destructive) {
                reader.resetWatchPairing()
            } label: {
                Text("Pair again", comment: "Confirm resetting the watch's sensor pairing")
            }
        }
        .onAppear {
            reader.noteWake()
        }
    }

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let latest = reader.latest {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(reader.format(Double(latest.glucose)))
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(reader.arrow(for: latest.trendName))
                        .font(.title3)
                    Text(reader.units)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(latest.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No reading from the watch yet", comment: "Watch G7 page: nothing read yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let problem = reader.sensorProblem {
                Text("Sensor: \(problem)", comment: "Watch G7 page: the sensor's state when it has no usable reading")
                    .font(.caption2)
                    .foregroundStyle(Color.loopYellow)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            row(
                String(localized: "Sensor", comment: "Watch G7 page label"),
                reader.sensorName ?? "–"
            )
            row(
                String(localized: "Code from iPhone", comment: "Watch G7 page label: pairing code received"),
                reader.pairingCode == nil ? "–" : "✓"
            )
            row(
                String(localized: "Watch paired", comment: "Watch G7 page label: the watch has its own key"),
                reader.hasWatchKey ? "✓" : "–"
            )
            row(
                String(localized: "Connected", comment: "Watch G7 page label"),
                reader.isConnected ? "✓" : "–"
            )
            row(
                String(localized: "iPhone data", comment: "Watch G7 page label: age of the last update from the phone"),
                reader.lastPhoneContact.map { minutesAgo($0) } ?? "–"
            )
        }
        .font(.caption2)
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Log", comment: "Watch G7 page: heading of the connection log")
                .font(.caption2)
                .fontWeight(.semibold)
            ForEach(Array(reader.logLines.suffix(25).reversed().enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func minutesAgo(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        return String(localized: "\(minutes) min ago", comment: "Watch G7 page: minutes since the last iPhone update")
    }
}
