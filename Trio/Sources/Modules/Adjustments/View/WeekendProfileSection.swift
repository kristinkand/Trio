import SwiftUI

/// A small, always-visible group of sections (deliberately separate from the Overrides list)
/// offering a "Weekend Profile" on/off toggle plus its own editable configuration -- see
/// `WeekendProfileStore` for what it actually does and how it interacts with Overrides/Temp
/// Targets.
///
/// Editing is a draft/Save flow: turning the master toggle on or off applies immediately (that's
/// the "start/stop" action, and also posts a "<name> started"/"ended" Note marker to Nightscout via
/// `state.uploadWeekendProfileNote(started:)`), but every other field here -- name, target,
/// SMB/UAM minutes, and the basal/ISF schedules -- is a local draft that's only written to
/// `WeekendProfileStore` when "Save the profile" is tapped, via `state.saveWeekendProfile`.
/// The very first time the editor is opened (before any Save), the draft's basal schedule, ISF
/// schedule, and SMB/UAM minutes are prefilled from the real settings rather than starting empty,
/// so there's a sensible starting point to tweak for the weekend. Carb ratio is never part of this
/// profile at all -- it always comes from the normal settings.
struct WeekendProfileSection: View {
    let state: Adjustments.StateModel

    private var units: GlucoseUnits { state.units }

    @State private var isActive = WeekendProfileStore.isActive
    @State private var name = WeekendProfileStore.name
    @State private var overrideTarget = WeekendProfileStore.target != 0
    @State private var target = WeekendProfileStore.target == 0 ? Decimal(100) : WeekendProfileStore.target
    @State private var smbMinutes = WeekendProfileStore.smbMinutes
    @State private var uamMinutes = WeekendProfileStore.uamMinutes
    @State private var basalEntries: [(minutes: Int, value: Decimal)] = []
    @State private var isfEntries: [(minutes: Int, value: Decimal)] = []
    @State private var didLoadDraft = false
    @State private var justSaved = false
    @State private var showInfo = false
    @FocusState private var isNameFieldFocused: Bool

    /// Finest raw step (1 mg/dL) in both unit systems -- matches the finest option Trio's own
    /// Override/Temp Target target pickers offer, instead of the coarse default (5 mg/dL / 9 raw
    /// units, ~0.5 mmol/L) they start with. Fixes the "can only change in 0.5 mmol/L jumps" issue.
    private var targetStep: Double { 1 }

    private static let basalRateStep = Decimal(string: "0.05") ?? 0.05
    /// 0.05...5.00 U/hr in 0.05 U/hr steps -- Weekend Profile's basal schedule feeds the dosing
    /// algorithm directly (see `OpenAPS.createProfiles()`), not the pump, so this doesn't need to
    /// match any specific pump's supported-rate list the way the real Basal Profile Editor does.
    private static let basalRateValues: [Decimal] = (1 ... 100).map { Decimal($0) * basalRateStep }

    private var isfValues: [Decimal] {
        PickerSettingsProvider.shared.generatePickerValues(
            from: PickerSetting(value: 100, step: 1, min: 9, max: 540, type: .glucose),
            units: units
        )
    }

    private func displayGlucose(_ value: Decimal) -> String {
        (units == .mgdL ? value.description : value.formattedAsMmolL) + " " + units.rawValue
    }

    private func isfLabel(_ value: Decimal) -> String {
        (units == .mgdL ? value.description : value.formattedAsMmolL) + " " + units.rawValue + "/U"
    }

    private func basalLabel(_ value: Decimal) -> String {
        String(format: "%.2f U/hr", NSDecimalNumber(decimal: value).doubleValue)
    }

    private func decimalStepper(
        title: String,
        value: Binding<Decimal>,
        range: ClosedRange<Double>,
        step: Double,
        display: @escaping (Decimal) -> String
    ) -> some View {
        Stepper(
            value: Binding(
                get: { Double(truncating: value.wrappedValue as NSNumber) },
                set: { value.wrappedValue = Decimal($0) }
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

    /// Loads the draft exactly once per appearance of the editor: from `WeekendProfileStore` if a
    /// profile has already been saved, otherwise prefilled from the real basal/ISF/SMB/UAM
    /// settings so the first edit starts from a working copy rather than nothing.
    private func loadDraftIfNeeded() {
        guard !didLoadDraft else { return }
        didLoadDraft = true

        if WeekendProfileStore.isConfigured {
            basalEntries = WeekendProfileStore.basalProfile.map { (minutes: $0.minutes, value: $0.rate) }
            isfEntries = (WeekendProfileStore.insulinSensitivities?.sensitivities ?? [])
                .map { (minutes: $0.offset, value: $0.sensitivity) }
        } else {
            basalEntries = state.currentBasalProfileForWeekendPrefill.map { (minutes: $0.minutes, value: $0.rate) }
            isfEntries = state.currentInsulinSensitivitiesForWeekendPrefill.sensitivities
                .map { (minutes: $0.offset, value: $0.sensitivity) }
            smbMinutes = state.defaultSmbMinutes
            uamMinutes = state.defaultUamMinutes
        }
    }

    private func startString(for minutes: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(minutes * 60)))
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let basalProfile = basalEntries.map { entry in
            BasalProfileEntry(start: startString(for: entry.minutes), minutes: entry.minutes, rate: entry.value)
        }
        let sensitivities = isfEntries.map { entry in
            InsulinSensitivityEntry(sensitivity: entry.value, offset: entry.minutes, start: startString(for: entry.minutes))
        }
        let insulinSensitivities = InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: sensitivities)

        state.saveWeekendProfile(
            name: trimmedName.isEmpty ? "Weekend Profile" : trimmedName,
            target: overrideTarget ? target : 0,
            smbMinutes: smbMinutes,
            uamMinutes: uamMinutes,
            basalProfile: basalProfile,
            insulinSensitivities: insulinSensitivities
        )
        justSaved = true
    }

    private var displayName: String { name.isEmpty ? "Weekend Profile" : name }

    private var infoText: String {
        "A name, target, SMB/UAM minutes, and its own basal + ISF schedule, that you start and stop yourself, independent of Overrides -- meant for stretches like a weekend or vacation. Carb ratio is never changed -- it always comes from your normal settings. If a real Override or Temp Target is running, it fully takes over the dosing math and Weekend Profile is paused until it ends."
    }

    var body: some View {
        Section {
            HStack {
                if isActive {
                    HStack(spacing: 4) {
                        TextField("Weekend Profile", text: $name)
                            .focused($isNameFieldFocused)
                            .onChange(of: name) { justSaved = false }
                            .toolbar {
                                // The keyboard otherwise covers the Save button below with no way
                                // to dismiss it -- this adds a "Done" button above the keyboard so
                                // editing the name doesn't strand you unable to scroll down.
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") {
                                        isNameFieldFocused = false
                                    }
                                }
                            }
                        Image(systemName: "pencil")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(displayName)
                }

                Spacer()

                Toggle("", isOn: $isActive)
                    .labelsHidden()
                    .accessibilityLabel(Text("\(displayName) Active"))
                    .onChange(of: isActive) {
                        WeekendProfileStore.isActive = isActive
                        state.uploadWeekendProfileNote(started: isActive)
                        Foundation.NotificationCenter.default.post(name: .didUpdateWeekendProfileConfiguration, object: nil)
                    }
            }

            if isActive {
                Toggle(isOn: $overrideTarget) {
                    Text("Override Target")
                }
                .onChange(of: overrideTarget) { justSaved = false }

                if overrideTarget {
                    decimalStepper(
                        title: "Target Glucose",
                        value: $target,
                        range: 72 ... 270,
                        step: targetStep,
                        display: displayGlucose
                    )
                    .onChange(of: target) { justSaved = false }
                }

                decimalStepper(
                    title: "SMB Minutes",
                    value: $smbMinutes,
                    range: 0 ... 180,
                    step: 5,
                    display: { "\($0.formatted(.number)) min" }
                )
                .onChange(of: smbMinutes) { justSaved = false }

                decimalStepper(
                    title: "UAM Minutes",
                    value: $uamMinutes,
                    range: 0 ... 180,
                    step: 5,
                    display: { "\($0.formatted(.number)) min" }
                )
                .onChange(of: uamMinutes) { justSaved = false }
            }
        } header: {
            HStack {
                Text(displayName)
                Spacer()
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showInfo) {
                    Text(infoText)
                        .padding()
                        .frame(width: 280)
                        .fixedSize(horizontal: false, vertical: true)
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        .listRowBackground(isActive ? Color.mint.opacity(0.15) : nil)
        .onAppear { loadDraftIfNeeded() }

        if isActive {
            WeekendScheduleEditor(
                title: "\(displayName) Basal",
                footer: "Absolute basal rates, same as the real Basal Profile Editor. Only used while Weekend Profile is active.",
                tint: .mint,
                valueValues: Self.basalRateValues,
                valueLabel: basalLabel,
                initialEntries: basalEntries,
                onChange: { basalEntries = $0; justSaved = false }
            )

            WeekendScheduleEditor(
                title: "\(displayName) ISF",
                footer: "Absolute insulin sensitivities, same as the real ISF Editor. Only used while Weekend Profile is active.",
                tint: .mint,
                valueValues: isfValues,
                valueLabel: isfLabel,
                initialEntries: isfEntries,
                onChange: { isfEntries = $0; justSaved = false }
            )

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Spacer()
                        Text(justSaved ? "Saved" : "Save the profile")
                        Spacer()
                    }
                }
                .disabled(justSaved)
            }
        }
    }
}
