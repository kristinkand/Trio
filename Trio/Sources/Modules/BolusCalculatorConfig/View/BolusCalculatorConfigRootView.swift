import CoreTransferable
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

// MARK: - Settings › Treatments › Treatment Sheet

extension TreatmentSheetRow: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }

    var title: String {
        switch self {
        case .carbs: String(localized: "Carbs")
        case .fatProtein: String(localized: "Fat and Protein")
        case .mealTime: String(localized: "Meal Time")
        case .note: String(localized: "Meal Note")
        case .bolusOptions: String(localized: "Reduced / Super Bolus")
        case .iob: String(localized: "Insulin on Board (IOB)")
        case .recommendation: String(localized: "Recommendation")
        case .bolus: String(localized: "Bolus")
        case .mealReminder: String(localized: "Remind Me to Eat")
        case .externalInsulin: String(localized: "External Insulin")
        }
    }

    var systemImage: String {
        switch self {
        case .carbs: "fork.knife"
        case .fatProtein: "takeoutbag.and.cup.and.straw"
        case .mealTime: "clock"
        case .note: "square.and.pencil"
        case .bolusOptions: "slider.horizontal.3"
        case .iob: "drop"
        case .recommendation: "wand.and.stars"
        case .bolus: "drop.fill"
        case .mealReminder: "alarm"
        case .externalInsulin: "syringe"
        }
    }
}

extension TreatmentSheetPill: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }

    var title: String {
        switch self {
        case .carbs: String(localized: "Carbs Entered")
        case .currentGlucose: String(localized: "Current Glucose")
        case .eventualGlucose: String(localized: "Eventual Glucose")
        case .iob: String(localized: "IOB")
        case .cob: String(localized: "COB")
        }
    }

    var systemImage: String {
        switch self {
        case .carbs: "fork.knife"
        case .currentGlucose: "drop.fill"
        case .eventualGlucose: "arrow.right.circle"
        case .iob: "syringe"
        case .cob: "fork.knife.circle"
        }
    }

    var sample: String {
        switch self {
        case .carbs: "45 g"
        case .currentGlucose: "120"
        case .eventualGlucose: "105"
        case .iob: "1.25 U"
        case .cob: "30 g"
        }
    }

    var color: Color {
        switch self {
        case .carbs: .orange
        case .currentGlucose: .blue
        case .eventualGlucose: .primary
        case .iob: Color.insulin
        case .cob: Color.loopYellow
        }
    }
}

/// Settings › Treatments › Treatment Sheet: a preview of the sheet to arrange, as for the Live Activity. Drag rows and
/// pills to move them, drag them up from the lists below to add them, or back down to remove them. Carbs, the
/// recommendation and the bolus always stay.
struct TreatmentSheetConfigView: BaseView {
    let resolver: Resolver

    @StateObject var state = BolusCalculatorConfig.StateModel()

    @State private var targetedRow: Int?
    @State private var targetedPill: Int?
    @State private var isPaletteTargeted = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    private var rows: [TreatmentSheetRow] { state.treatmentSheetRows }
    private var pills: [TreatmentSheetPill] { state.treatmentSheetPills }
    private var availableRows: [TreatmentSheetRow] { TreatmentSheetRow.defaultOrder.filter { !rows.contains($0) } }
    private var availablePills: [TreatmentSheetPill] { TreatmentSheetPill.allCases.filter { !pills.contains($0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Treatment Sheet Preview").uppercased())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading)

                preview

                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                    Text(
                        "Drag a row or pill to move it. Drag one up from the lists below to add it, or drop it back onto a list to remove it. Carbs, Recommendation and Bolus always stay."
                    )
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                palette
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .onAppear(perform: configureView)
        .navigationTitle("Treatment Sheet")
        .navigationBarTitleDisplayMode(.automatic)
    }

    // MARK: Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Close").foregroundStyle(Color.accentColor)
                Spacer()
                Text("Treatments").bold()
                Spacer()
                Toggle(isOn: $state.displayPresets) {
                    Text("Presets +").foregroundStyle(state.displayPresets ? Color.accentColor : Color.secondary)
                }
                .toggleStyle(.button)
                .accessibilityLabel(Text("Meal Presets Button"))
            }
            .font(.footnote)

            chartPreview

            VStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                    placedRow(row, at: index)
                }
                rowDropZone(at: rows.count)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.chart))
    }

    @ViewBuilder private var chartPreview: some View {
        if state.showTreatmentChart {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(pills.enumerated()), id: \.element) { index, pill in
                        placedPill(pill, at: index)
                    }
                    if pills.count < TreatmentSheetPill.limit {
                        emptyPillSlot(at: pills.count)
                    }
                }
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.cyan.opacity(0.12))
                        .frame(height: 70)
                        .overlay(
                            Label("Forecast Chart", systemImage: "chart.xyaxis.line")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        )
                    removeBadge(String(localized: "Forecast Chart")) { state.showTreatmentChart = false }
                }
            }
        } else {
            Button {
                withAnimation { state.showTreatmentChart = true }
            } label: {
                Label("Forecast Chart and Pills", systemImage: "plus")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(style: StrokeStyle(lineWidth: 1, dash: [5])))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func removeBadge(_ title: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation { action() } } label: {
            Image(systemName: "trash.circle.fill")
                .foregroundStyle(Color(UIColor.systemGray2))
                .background(Circle().fill(Color.white))
                .font(.title3)
        }
        .buttonStyle(.plain)
        .offset(x: 8, y: -8)
        .accessibilityLabel(Text("Remove \(title)"))
    }

    private func pillTile(_ pill: TreatmentSheetPill, highlighted: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: pill.systemImage)
            Text(pill.sample).lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(pill.color)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).fill(pill.color.opacity(0.2)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: highlighted ? 2 : 0))
    }

    private func placedPill(_ pill: TreatmentSheetPill, at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            pillTile(pill, highlighted: targetedPill == index)
            removeBadge(pill.title) { _ = removePill(pill) }
        }
        .frame(maxWidth: .infinity)
        .draggable(pill) { pillTile(pill) }
        .dropDestination(for: TreatmentSheetPill.self) { dropped, _ in
            targetedPill = nil
            guard let dropped = dropped.first else { return false }
            return placePill(dropped, at: index)
        } isTargeted: { targetedPill = $0 ? index : nil }
        .contextMenu {
            if index > 0 { Button("Move Left") { _ = placePill(pill, at: index - 1) } }
            if index < pills.count - 1 { Button("Move Right") { _ = placePill(pill, at: index + 2) } }
            Button("Remove", role: .destructive) { _ = removePill(pill) }
        }
        .accessibilityLabel(Text(pill.title))
        .accessibilityValue(Text("Pill \(index + 1) of \(pills.count)"))
    }

    private func emptyPillSlot(at index: Int) -> some View {
        Image(systemName: "plus")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(style: StrokeStyle(lineWidth: targetedPill == index ? 2 : 1, dash: targetedPill == index ? [] : [4]))
                    .foregroundStyle(targetedPill == index ? Color.accentColor : Color.secondary)
            )
            .dropDestination(for: TreatmentSheetPill.self) { dropped, _ in
                targetedPill = nil
                guard let dropped = dropped.first else { return false }
                return placePill(dropped, at: pills.count)
            } isTargeted: { targetedPill = $0 ? index : nil }
            .accessibilityLabel(Text("Empty pill slot"))
    }

    /// Why a row on the sheet doesn't show yet: its feature is off elsewhere.
    private func missingFeature(_ row: TreatmentSheetRow) -> String? {
        switch row {
        case .fatProtein where !state.useFPUconversion:
            String(localized: "Shows once Fat and Protein Entries are on (Meal Settings)")
        case .bolusOptions where !state.fattyMeals && !state.sweetMeals:
            String(localized: "Shows once Reduced or Super Bolus is on (Bolus Calculator)")
        case .mealReminder where !state.mealTimeReminderEnabled:
            String(localized: "Shows once the Meal-Time Reminder is on (Bolus Calculator)")
        default:
            nil
        }
    }

    private func rowTile(_ row: TreatmentSheetRow, highlighted: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.subheadline)
                if let missing = missingFeature(row) {
                    Text(missing).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if row.isRequired {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: highlighted ? 2 : 0))
        .opacity(missingFeature(row) == nil ? 1 : 0.6)
    }

    private func placedRow(_ row: TreatmentSheetRow, at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            rowTile(row, highlighted: targetedRow == index)
            if !row.isRequired {
                removeBadge(row.title) { _ = removeRow(row) }
            }
        }
        .draggable(row) { rowTile(row).frame(width: 260) }
        .dropDestination(for: TreatmentSheetRow.self) { dropped, _ in
            targetedRow = nil
            guard let dropped = dropped.first else { return false }
            return placeRow(dropped, at: index)
        } isTargeted: { targetedRow = $0 ? index : nil }
        .contextMenu {
            if index > 0 { Button("Move Up") { _ = placeRow(row, at: index - 1) } }
            if index < rows.count - 1 { Button("Move Down") { _ = placeRow(row, at: index + 2) } }
            if !row.isRequired { Button("Remove", role: .destructive) { _ = removeRow(row) } }
        }
        .accessibilityLabel(Text(row.title))
        .accessibilityValue(Text("Row \(index + 1) of \(rows.count)"))
    }

    private func rowDropZone(at index: Int) -> some View {
        Text("Drop here to put it last")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style: StrokeStyle(lineWidth: targetedRow == index ? 2 : 1, dash: targetedRow == index ? [] : [4]))
                    .foregroundStyle(targetedRow == index ? Color.accentColor : Color.secondary)
            )
            .dropDestination(for: TreatmentSheetRow.self) { dropped, _ in
                targetedRow = nil
                guard let dropped = dropped.first else { return false }
                return placeRow(dropped, at: rows.count)
            } isTargeted: { targetedRow = $0 ? index : nil }
    }

    // MARK: Palette

    private var palette: some View {
        VStack(alignment: .leading, spacing: 12) {
            pillPalette
            rowPalette
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(isPaletteTargeted ? 0.25 : 0.1)))
    }

    private var pillPalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Available Pills").uppercased())
                .font(.footnote)
                .foregroundStyle(.secondary)
            if availablePills.isEmpty {
                Text("All pills are on the sheet.").font(.caption).foregroundStyle(.secondary)
            } else {
                FlowRow(items: availablePills) { pill in
                    let canPlace = pills.count < TreatmentSheetPill.limit && state.showTreatmentChart
                    VStack(spacing: 4) {
                        pillTile(pill)
                        Text(pill.title).font(.caption2).foregroundStyle(.secondary)
                    }
                    .opacity(canPlace ? 1 : 0.4)
                    .onTapGesture { if canPlace { _ = placePill(pill, at: pills.count) } }
                    .draggable(pill) { pillTile(pill) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(pill.title))
                    .accessibilityHint(Text(canPlace ? "Adds this pill above the chart" : "No room for another pill"))
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .dropDestination(for: TreatmentSheetPill.self) { dropped, _ in
            isPaletteTargeted = false
            guard let dropped = dropped.first else { return false }
            return removePill(dropped)
        } isTargeted: { isPaletteTargeted = $0 }
    }

    private var rowPalette: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Available Rows").uppercased())
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            if availableRows.isEmpty {
                Text("All rows are on the sheet.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(availableRows) { row in
                    rowTile(row)
                        .onTapGesture { _ = placeRow(row, at: rows.count) }
                        .draggable(row) { rowTile(row).frame(width: 260) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text("Adds this row at the end of the sheet"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .dropDestination(for: TreatmentSheetRow.self) { dropped, _ in
            isPaletteTargeted = false
            guard let dropped = dropped.first else { return false }
            return removeRow(dropped)
        } isTargeted: { isPaletteTargeted = $0 }
    }

    // MARK: Changes

    @discardableResult private func placeRow(_ row: TreatmentSheetRow, at index: Int) -> Bool {
        var items = rows
        var target = index
        if let current = items.firstIndex(of: row) {
            guard current != index else { return false }
            items.remove(at: current)
            if current < target { target -= 1 }
        }
        items.insert(row, at: min(max(target, 0), items.count))
        withAnimation { state.treatmentSheetRows = TreatmentSheetRow.normalized(items) }
        return true
    }

    @discardableResult private func removeRow(_ row: TreatmentSheetRow) -> Bool {
        guard !row.isRequired, rows.contains(row) else { return false }
        withAnimation { state.treatmentSheetRows = rows.filter { $0 != row } }
        return true
    }

    @discardableResult private func placePill(_ pill: TreatmentSheetPill, at index: Int) -> Bool {
        var items = pills
        var target = index
        if let current = items.firstIndex(of: pill) {
            guard current != index else { return false }
            items.remove(at: current)
            if current < target { target -= 1 }
        } else {
            guard items.count < TreatmentSheetPill.limit else { return false }
        }
        items.insert(pill, at: min(max(target, 0), items.count))
        withAnimation { state.treatmentSheetPills = TreatmentSheetPill.normalized(items) }
        return true
    }

    @discardableResult private func removePill(_ pill: TreatmentSheetPill) -> Bool {
        guard pills.contains(pill) else { return false }
        withAnimation { state.treatmentSheetPills = pills.filter { $0 != pill } }
        return true
    }
}

/// Items laid out left to right, wrapping onto new lines.
private struct FlowRow<Item: Identifiable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(items) { content($0) }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
