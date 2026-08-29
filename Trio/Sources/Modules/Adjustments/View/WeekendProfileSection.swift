import SwiftUI

/// A small, always-visible section (deliberately separate from the Overrides list) offering a
/// single "Weekend Profile" on/off toggle -- see `WeekendProfileStore` for what it actually does
/// and how it interacts with Overrides. Flipping the toggle also posts a "Weekend Profile
/// started"/"ended" Note marker to Nightscout via `state.uploadWeekendProfileNote(started:)`.
struct WeekendProfileSection: View {
    let state: Adjustments.StateModel

    private var units: GlucoseUnits { state.units }

    @State private var isActive = WeekendProfileStore.isActive
    @State private var percentage = WeekendProfileStore.percentage
    @State private var overrideTarget = WeekendProfileStore.target != 0
    @State private var target = WeekendProfileStore.target == 0 ? Decimal(100) : WeekendProfileStore.target
    @State private var smbMinutes = WeekendProfileStore.smbMinutes
    @State private var uamMinutes = WeekendProfileStore.uamMinutes

    private var targetStep: Double { units == .mgdL ? 5 : 9 }

    private func displayGlucose(_ value: Decimal) -> String {
        (units == .mgdL ? value.description : value.formattedAsMmolL) + " " + units.rawValue
    }

    private func decimalStepper(
        title: String,
        value: Binding<Decimal>,
        range: ClosedRange<Double>,
        step: Double,
        display: @escaping (Decimal) -> String,
        onChange: @escaping (Decimal) -> Void
    ) -> some View {
        Stepper(
            value: Binding(
                get: { Double(truncating: value.wrappedValue as NSNumber) },
                set: { newValue in
                    let decimal = Decimal(newValue)
                    value.wrappedValue = decimal
                    onChange(decimal)
                }
            ),
            in: range,
            step: step
        ) {
            HStack {
                Text(title)
                Spacer()
                Text(display(value.wrappedValue)).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        Section {
            Toggle(isOn: $isActive) {
                Text("Weekend Profile")
            }
            .onChange(of: isActive) {
                WeekendProfileStore.isActive = isActive
                state.uploadWeekendProfileNote(started: isActive)
            }

            if isActive {
                decimalStepper(
                    title: "Percentage",
                    value: $percentage,
                    range: 40 ... 150,
                    step: 5,
                    display: { "\($0.formatted(.number)) %" },
                    onChange: { WeekendProfileStore.percentage = $0 }
                )

                Toggle(isOn: $overrideTarget) {
                    Text("Override Target")
                }
                .onChange(of: overrideTarget) {
                    WeekendProfileStore.target = overrideTarget ? target : 0
                }

                if overrideTarget {
                    decimalStepper(
                        title: "Target Glucose",
                        value: $target,
                        range: 72 ... 270,
                        step: targetStep,
                        display: displayGlucose,
                        onChange: { WeekendProfileStore.target = $0 }
                    )
                }

                decimalStepper(
                    title: "SMB Minutes",
                    value: $smbMinutes,
                    range: 0 ... 180,
                    step: 5,
                    display: { "\($0.formatted(.number)) min" },
                    onChange: { WeekendProfileStore.smbMinutes = $0 }
                )

                decimalStepper(
                    title: "UAM Minutes",
                    value: $uamMinutes,
                    range: 0 ... 180,
                    step: 5,
                    display: { "\($0.formatted(.number)) min" },
                    onChange: { WeekendProfileStore.uamMinutes = $0 }
                )
            }
        } header: {
            Text("Weekend Profile")
        } footer: {
            Text(
                "A percentage, target, and SMB/UAM minutes you start and stop yourself, independent of Overrides -- meant for stretches like a weekend or vacation. If a real Override is running (e.g. a low-recovery override), it fully takes over the dosing math and Weekend Profile is paused until that Override ends."
            )
        }
        .listRowBackground(isActive ? Color.loopGreen.opacity(0.15) : nil)
    }
}
