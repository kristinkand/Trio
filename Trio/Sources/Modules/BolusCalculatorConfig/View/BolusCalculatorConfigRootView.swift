import SwiftUI
import Swinject

extension BolusCalculatorConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.displayPresets,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Display Meal Presets")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Display Meal Presets"),
                    miniHint: String(localized: "Allow the creation of saved, preset meals."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: ON").bold()
                        Text("Enabling this feature allows you to create and save preset meals.")
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.showMealTime,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Show Meal Time")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Show Meal Time"),
                    miniHint: String(localized: "Show the time row for meal entries in the bolus calculator."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: ON").bold()
                        Text(
                            "Shows the time row in the bolus calculator so a meal can be logged at an earlier or later time."
                        )
                        Text(
                            "When turned off, meals are always logged at the time the bolus calculator was opened."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.showMealNote,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Show Meal Note")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Show Meal Note"),
                    miniHint: String(localized: "Show the note field for meal entries in the bolus calculator."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: ON").bold()
                        Text("Shows the note field in the bolus calculator so a short note can be added to a meal entry.")
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.showExternalInsulin,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Show External Insulin")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Show External Insulin"),
                    miniHint: String(localized: "Show the External Insulin option in the bolus calculator."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: ON").bold()
                        Text(
                            "Shows the External Insulin option in the bolus calculator for logging insulin given outside the pump, for example with a pen or syringe."
                        )
                        Text("When turned off, every bolus entered in the bolus calculator is delivered by the pump.")
                        Text("Keep this on if you log injections given with a pen or syringe.")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.overrideFactor,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Recommended Bolus Percentage")
                        }
                    ),
                    units: state.units,
                    type: .decimal("overrideFactor"),
                    label: String(localized: "Recommended Bolus Percentage"),
                    miniHint: String(localized: "Percentage of bolus suggested in bolus calculator."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 80%").bold()
                        Text(
                            "Recommended Bolus Percentage is a safety feature built into Trio. Trio first calculates an insulin required value, which is the full dosage. That dosage is then multiplied by your Recommended Bolus Percentage to display your suggested insulin dose in the bolus calculator."
                        )
                        Text(
                            "Because Trio utilizes SMBs and UAM SMBs to help you reach your target glucose and other AID systems do not bolus for COB the same way Trio does, this is initially set to below the full calculated amount (80%). When SMBs and UAM SMBs are enabled, you may find your current CR results in lows and needs to be increased before you increase this setting closer to or at 100%."
                        )
                        Text(
                            "Tip: If you are a new Trio user, it is not advised to set this to 100% until you have verified that your core settings (basal rates, ISF, and CR) do not need adjusting."
                        )
                    },
                    headerText: String(localized: "Calculator Configuration")
                )

                SettingInputSection(
                    decimalValue: $state.fattyMealFactor,
                    booleanValue: $state.fattyMeals,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Reduced Bolus")
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("fattyMealFactor"),
                    label: String(localized: "Enable Reduced Bolus Option"),
                    conditionalLabel: String(localized: "Reduced Bolus Percentage"),
                    miniHint: String(localized: "Add and set a bolus option for meals that absorb slowly."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("Default Percent: 70%").bold()
                        Text("Do not enable this feature until you have optimized your CR (carb ratio) setting.").bold()
                        Text(
                            "Enabling this setting adds a \"Reduced Bolus\" option to the bolus calculator. Once this feature is enabled, a percentage setting will appear for you to select."
                        )
                        Text(
                            "When \"Reduced Bolus\" is selected in the bolus calculator, the recommended bolus will be multiplied by the \"Reduced Bolus Percentage\" as well as the \"Recommended Bolus Percentage\"."
                        )
                        Text(
                            "If you have a \"Recommended Bolus Percentage\" of 80%, and a \"Reduced Bolus Percentage\" of 70%, your recommended bolus will be multiplied by: (80 × 70) / 100 = 56%."
                        )
                        Text(
                            "This is useful for slow-absorbing meals where high fat, protein, or fiber can delay carb absorption and cause a slower rise in blood sugar, so a reduced bolus helps match insulin to the delayed effect."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.sweetMealFactor,
                    booleanValue: $state.sweetMeals,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Super Bolus")
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("sweetMealFactor"),
                    label: String(localized: "Enable Super Bolus Option"),
                    conditionalLabel: String(localized: "Super Bolus Percentage"),
                    miniHint: String(localized: "Add and set a bolus option for meals that absorb quickly."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text("Default Percent: 100%").bold()
                        Text("Do not enable this feature until you have optimized your CR (carb ratio) setting.").bold()
                        Text(
                            "Enabling this setting adds a \"Super Bolus\" option to the bolus calculator. Once this feature is enabled, a percentage setting will appear for you to select."
                        )
                        Text(
                            "When \"Super Bolus\" is selected in the bolus calculator, your current basal rate multiplied by \"Super Bolus Percentage\" will be added to your bolus recommendation."
                        )
                        Text(
                            "If your current basal rate is 0.8 U/hr and \"Super Bolus Percentage\" is set to 200%: 0.8 × (200 / 100) = 1.6 units will be added to your bolus recommendation."
                        )
                        Text("This could be useful for fast absorbing meals like sugary cereal.")
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.confirmBolusWhenVeryLowGlucose,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Very Low Glucose Bolus Warning")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Very Low Glucose Warning"),
                    miniHint: String(
                        localized: "Warning when bolusing with a very low or forecasted very low glucose."
                    ),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        Text(
                            "Triggers a confirmation dialog if you attempt to bolus when glucose is < \(54.formatted(for: state.units)) \(state.units.rawValue)."
                        )
                        Text(
                            "Also triggered when the lowest forecasted glucose (minPredBG) is < \(54.formatted(for: state.units)) \(state.units.rawValue)."
                        )
                        Text(
                            "Note: The forecast used for this warning does not include carbs or insulin that have been logged but not yet effective."
                        )
                    }
                )

                Section {
                    Toggle(isOn: $state.podChangeReminderEnabled) {
                        Text("Pod Change Reminder")
                    }
                } footer: {
                    Text(
                        "\"Change pump!\" when the pod is 2 days and 6 hours old, as an alarm that rings until it is stopped. If that falls between 22:00 and 07:00, it rings at 07:00."
                    )
                }
                .listRowBackground(Color.chart)

                Section {
                    VStack {
                        HStack {
                            Toggle(isOn: $state.mealTimeReminderEnabled) {
                                Text("Enable Meal-Time Reminder Option")
                            }
                        }.padding(.top)

                        SettingHintRow(
                            miniHint: String(
                                localized: "Set a lead time between bolusing and eating, with an alarm when it is time to eat."
                            ),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = String(localized: "Meal-Time Reminder")
                                }
                            ),
                            verboseHint: VStack(alignment: .leading, spacing: 10) {
                                Text("Default: OFF").bold()
                                Text(
                                    "Enabling this option adds a \"Remind Me to Eat\" row to the bolus calculator. When enabled for a meal, it lets you set a timer based on your configured presets."
                                )
                                Text(
                                    "Set how many minutes before eating you want to bolus. The reminder starts off for each meal. Once the bolus is confirmed, an alarm counts down until it is time to eat."
                                )
                            },
                            label: String(localized: "Enable Meal-Time Reminder Option")
                        )
                    }
                } header: {
                    Text("Meal-Time Reminder")
                }
                .settingsSearchTarget(label: String(localized: "Enable Meal-Time Reminder Option"))

                if state.mealTimeReminderEnabled {
                    Section {
                        ForEach($state.mealTimeReminderPresets, id: \.self) { $preset in
                            // Presets are deduplicated on save, so matching by value (rather than
                            // a captured array index, which can go stale mid swipe-to-delete
                            // animation and crash) is safe.
                            let position = (state.mealTimeReminderPresets.firstIndex(of: preset) ?? 0) + 1
                            PickerSettingRow(
                                label: String(
                                    localized: "Preset \(position)",
                                    comment: "Numbered meal-time reminder preset button"
                                ),
                                decimalValue: $preset,
                                setting: PickerSettingsProvider.shared.settings.mealTimeReminderPreset,
                                units: state.units
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if state.mealTimeReminderPresets.count > 1 {
                                    Button(role: .destructive) {
                                        state.mealTimeReminderPresets.removeAll { $0 == preset }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                            }
                        }

                        let presetLimitReached = state.mealTimeReminderPresets.count >= TrioSettings.mealTimeReminderPresetLimit
                        Button {
                            let next = min((state.mealTimeReminderPresets.max() ?? 5) + 5, 60)
                            guard !state.mealTimeReminderPresets.contains(next) else { return }
                            state.mealTimeReminderPresets.append(next)
                        } label: {
                            Label("Add Preset", systemImage: "plus.circle.fill")
                        }
                        .disabled(presetLimitReached)
                        .foregroundStyle(presetLimitReached ? Color.secondary : Color.accentColor)
                    } footer: {
                        Text("Quick buttons for the reminder lead time. Add up to 3 presets, swipe to delete.")
                    }
                    .listRowBackground(Color.chart)
                }
            }
            .listSectionSpacing(sectionSpacing)
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationBarTitle("Bolus Calculator")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
        }
    }
}

/// Settings › Treatments › Treatment Sheet: which optional parts the treatment sheet shows. Carbs, the
/// recommendation and the bolus are always there; the rest is picked from a list, as for the Live Activity.
struct TreatmentSheetConfigView: BaseView {
    let resolver: Resolver

    @StateObject var state = BolusCalculatorConfig.StateModel()

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    /// The optional parts, in the order the sheet shows them.
    enum Item: CaseIterable, Identifiable {
        case chart
        case fatProtein
        case mealTime
        case note
        case bolusOptions
        case iob
        case mealReminder
        case externalInsulin
        case presets

        var id: Self { self }

        var title: String {
            switch self {
            case .chart: String(localized: "Forecast Chart")
            case .fatProtein: String(localized: "Fat and Protein")
            case .mealTime: String(localized: "Meal Time")
            case .note: String(localized: "Meal Note")
            case .bolusOptions: String(localized: "Reduced Bolus / Super Bolus")
            case .iob: String(localized: "Insulin on Board (IOB)")
            case .mealReminder: String(localized: "Remind Me to Eat")
            case .externalInsulin: String(localized: "External Insulin")
            case .presets: String(localized: "Meal Presets Button")
            }
        }

        var systemImage: String {
            switch self {
            case .chart: "chart.xyaxis.line"
            case .fatProtein: "fork.knife"
            case .mealTime: "clock"
            case .note: "square.and.pencil"
            case .bolusOptions: "slider.horizontal.3"
            case .iob: "drop"
            case .mealReminder: "alarm"
            case .externalInsulin: "syringe"
            case .presets: "plus.rectangle.on.rectangle"
            }
        }
    }

    private func isShown(_ item: Item) -> Binding<Bool> {
        switch item {
        case .chart: $state.showTreatmentChart
        case .fatProtein: $state.showTreatmentFatProtein
        case .mealTime: $state.showMealTime
        case .note: $state.showMealNote
        case .bolusOptions: $state.showTreatmentBolusOptions
        case .iob: $state.showTreatmentIOB
        case .mealReminder: $state.showTreatmentMealReminder
        case .externalInsulin: $state.showExternalInsulin
        case .presets: $state.displayPresets
        }
    }

    /// Why a part chosen here can't appear yet: the feature behind it is off elsewhere.
    private func missingFeature(_ item: Item) -> String? {
        switch item {
        case .fatProtein where !state.useFPUconversion:
            String(localized: "Needs Fat and Protein Entries (Meal Settings)")
        case .bolusOptions where !state.fattyMeals && !state.sweetMeals:
            String(localized: "Needs Reduced or Super Bolus (Bolus Calculator)")
        case .mealReminder where !state.mealTimeReminderEnabled:
            String(localized: "Needs the Meal-Time Reminder (Bolus Calculator)")
        default:
            nil
        }
    }

    @ViewBuilder private func row(_ item: Item, shown: Bool) -> some View {
        HStack {
            Button {
                withAnimation { isShown(item).wrappedValue = !shown }
            } label: {
                Image(systemName: shown ? "minus.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(shown ? Color.red : Color.green)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(shown ? "Remove \(item.title)" : "Add \(item.title)"))

            Image(systemName: item.systemImage)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if let missing = missingFeature(item) {
                    Text(missing).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(
                    [
                        (String(localized: "Carbs"), "fork.knife.circle"),
                        (String(localized: "Recommendation"), "wand.and.stars"),
                        (String(localized: "Bolus"), "drop.fill")
                    ],
                    id: \.0
                ) { title, image in
                    HStack {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary).font(.title3)
                        Image(systemName: image).frame(width: 24).foregroundStyle(.secondary)
                        Text(title)
                    }
                }
            } header: {
                Text("Always Shown")
            }
            .listRowBackground(Color.chart)

            let shown = Item.allCases.filter { isShown($0).wrappedValue }
            let available = Item.allCases.filter { !isShown($0).wrappedValue }

            Section {
                if shown.isEmpty {
                    Text("Only carbs, the recommendation and the bolus.").foregroundStyle(.secondary)
                }
                ForEach(shown) { row($0, shown: true) }
            } header: {
                Text("Shown on the Treatment Sheet")
            } footer: {
                Text("The sheet keeps its order: the meal entries first, then the bolus.")
            }
            .listRowBackground(Color.chart)

            if !available.isEmpty {
                Section {
                    ForEach(available) { row($0, shown: false) }
                } header: {
                    Text("Available")
                }
                .listRowBackground(Color.chart)
            }
        }
        .listSectionSpacing(sectionSpacing)
        .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
        .onAppear(perform: configureView)
        .navigationBarTitle("Treatment Sheet")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
