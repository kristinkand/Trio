import CoreData
import SwiftUI

extension History.RootView {
    var placementLogList: some View {
        List {
            HStack {
                Text("Location").foregroundStyle(.secondary)
                Spacer()
                Text("Time").foregroundStyle(.secondary)
            }

            if !placementLogStored.isEmpty {
                ForEach(placementLogStored) { item in
                    placementLogView(item)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "No data."),
                    systemImage: "bandage"
                )
            }
        }.listRowBackground(Color.chart)
    }

    @ViewBuilder func placementLogView(_ entry: PlacementLogStored) -> some View {
        HStack {
            Image(systemName: entry.deviceTypeEnum == .pump ? "syringe.fill" : "sensor.tag.radiowaves.forward.fill")
                .foregroundStyle(entry.deviceTypeEnum == .pump ? Color.blue : Color.orange)

            VStack(alignment: .leading) {
                Text(entry.locationEnum.fullDisplayName)
                HStack(spacing: 6) {
                    if entry.hasSiteIssue {
                        Label("Site Issue", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if entry.isPainful {
                        Label("Painful", systemImage: "bolt.heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            Text(Formatter.dateFormatter.string(from: entry.date ?? Date()))
        }
        .swipeActions {
            Button(
                "Delete",
                systemImage: "trash.fill",
                role: .none,
                action: { state.deletePlacementLog(entry.objectID) }
            ).tint(.red)
        }
    }
}
