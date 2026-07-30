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
        Menu {
            Button {
                state.startEditingPlacementLog(entry)
                showAddPlacementLog = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                state.deletePlacementLog(entry.objectID)
            } label: {
                Label("Delete", systemImage: "trash.fill")
            }
        } label: {
            HStack {
                Image(systemName: entry.deviceTypeEnum == .pump ? "syringe.fill" : "sensor.tag.radiowaves.forward.fill")
                    .foregroundStyle(entry.deviceTypeEnum == .pump ? Color.blue : Color.orange)

                VStack(alignment: .leading) {
                    Text(entry.locationEnum.fullDisplayName)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if entry.hasSiteIssue {
                            Label("Site Issue", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if entry.isPainfulGivingInsulin {
                            Label("Painful (Insulin)", systemImage: "bolt.heart.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if entry.isPainful {
                            Label("Painful (Wearing)", systemImage: "bolt.heart.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Spacer()

                Text(Formatter.dateFormatter.string(from: entry.date ?? Date()))
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
