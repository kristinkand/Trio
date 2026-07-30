import SwiftUI

extension History.RootView {
    var visiblePlacementRegions: [PlacementBodyRegion] {
        state.newPlacementDeviceType == .sensor ? [.upperArm, .thigh] : PlacementBodyRegion.allCases
    }

    @ViewBuilder func addPlacementLogView() -> some View {
        NavigationView {
            Form {
                Section {
                    Picker("Device", selection: $state.newPlacementDeviceType) {
                        ForEach(PlacementDeviceType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                        .onChange(of: state.newPlacementDeviceType) { newValue in
                            if newValue == .sensor {
                                if !visiblePlacementRegions.contains(state.newPlacementLocation.region) {
                                    state.newPlacementLocation = .upperArmLeft
                                }
                                state.newPlacementIsPainfulGivingInsulin = false
                            }
                        }
                }.listRowBackground(Color.chart)

                ForEach(visiblePlacementRegions) { region in
                    Section(region.displayName) {
                        ForEach(PlacementLocation.locations(in: region)) { location in
                            HStack {
                                Text(location.displayName)
                                Spacer()
                                if state.newPlacementLocation == location {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.newPlacementLocation = location
                            }
                        }
                    }.listRowBackground(Color.chart)
                }

                Section {
                    Toggle("Site Issue", isOn: $state.newPlacementHasSiteIssue)
                    if state.newPlacementDeviceType == .pump {
                        Toggle("Painful (Giving Insulin)", isOn: $state.newPlacementIsPainfulGivingInsulin)
                    }
                    Toggle("Painful (Wearing)", isOn: $state.newPlacementIsPainful)
                }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        Button {
                            state.savePlacementLog()
                            showAddPlacementLog = false
                            state.mode = .placementLog
                        }
                        label: { Text("Save") }
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .listRowBackground(Color(.systemBlue))
                .tint(.white)
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(state.editingPlacementLogObjectID != nil ? "Edit Placement" : "Log Placement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        state.resetNewPlacementLogFields()
                        showAddPlacementLog = false
                    }
                }
            }
        }
    }
}
