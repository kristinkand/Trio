import SwiftUI

extension History.RootView {
    @ViewBuilder func addPlacementLogView() -> some View {
        NavigationView {
            Form {
                Section {
                    Picker("Device", selection: $state.newPlacementDeviceType) {
                        ForEach(PlacementDeviceType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                }.listRowBackground(Color.chart)

                ForEach(PlacementBodyRegion.allCases) { region in
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
                    Toggle("Painful", isOn: $state.newPlacementIsPainful)
                }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        Button {
                            state.addPlacementLog()
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
            .navigationTitle("Log Placement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        showAddPlacementLog = false
                    }
                }
            }
        }
    }
}
