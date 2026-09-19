import SwiftUI

extension History.RootView {
    var visiblePlacementRegions: [PlacementBodyRegion] {
        state.newPlacementDeviceType == .sensor ? [.upperArm, .abdomen, .thigh] : PlacementBodyRegion.allCases
    }

    @ViewBuilder func addPlacementLogView() -> some View {
        NavigationView {
            Form {
                Section {
                    DatePicker(
                        "Date",
                        selection: $state.newPlacementDate,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }.listRowBackground(Color.chart)

                Section {
                    Picker("Device", selection: $state.newPlacementDeviceType) {
                        ForEach(PlacementDeviceType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                        .onChange(of: state.newPlacementDeviceType) { newValue in
                            // Reset the selected location whenever it isn't valid for the new
                            // device type -- either its region is hidden for this type (e.g.
                            // Buttocks for sensor), or the location itself doesn't apply (e.g.
                            // the pump-only abdomen quadrants vs. the sensor-only single
                            // Abdomen entry).
                            if !visiblePlacementRegions.contains(state.newPlacementLocation.region) ||
                                !state.newPlacementLocation.deviceTypes.contains(newValue)
                            {
                                state.newPlacementLocation = .upperArmLeft
                            }
                            if newValue == .sensor {
                                state.newPlacementIsPainfulGivingInsulin = false
                            } else {
                                state.newPlacementHasInaccurateReadings = false
                            }
                        }
                }.listRowBackground(Color.chart)

                ForEach(visiblePlacementRegions) { region in
                    Section(region.displayName) {
                        ForEach(PlacementLocation.locations(in: region, for: state.newPlacementDeviceType)) { location in
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
                    if state.newPlacementDeviceType == .sensor {
                        Toggle("Inaccurate Readings", isOn: $state.newPlacementHasInaccurateReadings)
                    }
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
