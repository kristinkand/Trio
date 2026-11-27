import CoreTransferable
import SwiftUI
import Swinject
import UniformTypeIdentifiers

struct WatchConfigAppleWatchView: BaseView {
    static let cornerLabelHint = String(
        localized: "Corner Label is the curved text on Trio Glucose corner slots."
    )
    static let smallLineHint = String(
        localized: "Small Line is the text under the glucose on Trio Glucose circular slots, beside the ring on Trio Gauge rectangular slots, and the second line of Trio Chart. Trio IOB has a fixed layout."
    )
    static let markStaleAfterHint = String(
        localized: "Mark Stale After applies to every complication: once the reading is older than this, the glucose shows -- with the reading's age, and IOB and COB show -- when the loop has not run within that time.\n\nComplications can fall behind the phone, sometimes by a lot: with the watch app closed, watchOS limits how often they refresh. The Contact Image updates with every reading, so use it if you want every reading on your watch face."
    )
    static let colorModeHint = String(
        localized: "Color: the glucose number uses the same colors as the Trio app on your iPhone.\n\nMonochrome: the glucose number is white. This can be easier to read in the dark.\n\nThe ring and the chart line always keep their colors. Small text, like the trend arrow, is always white."
    )
    static let contactImageHint = String(
        localized: "Use this when the Trio complications fall behind. Your watch only lets complications update a few times an hour, so they can show old numbers. The Contact Image does not have this limit: it changes with every new reading.\n\nTrio draws your data into the photo of a contact on your iPhone. You pick what it shows, like glucose, trend, IOB, COB or the last loop. Add that contact to a watch face with the Contacts complication."
    )

    static func readOnWatchHint(cgmName: String) -> String {
        String(
            localized: "Your watch can get readings straight from your \(cgmName). This helps when your iPhone is out of reach.\n\nYour watch shows the readings from your iPhone first. If they stop coming, your watch reads the sensor itself. You then see a small watch symbol in the glucose bubble.\n\nTo turn this on or off, open your \(cgmName) settings and use “Read on Apple Watch”."
        )
    }

    let resolver: Resolver
    @ObservedObject var state: WatchConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: AnyView?
    @State var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    private func onDelete(offsets: IndexSet) {
        state.devices.remove(atOffsets: offsets)
        state.deleteGarminDevice()
    }

    private var previewState: ComplicationState {
        ComplicationState.sample(
            units: state.units.rawValue,
            settings: ComplicationSlotSettings(
                cornerValue: state.complicationCornerValue,
                secondaryValue: state.complicationSecondaryValue,
                staleMinutes: state.complicationStaleMinutes,
                colorMode: state.complicationColorMode
            ),
            ringStops: state.complicationRingStops
        )
    }

    private func hintRow(miniHint: String, label: String, hint: String) -> some View {
        HStack(alignment: .center) {
            Text(miniHint)
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(
                action: {
                    hintLabel = label
                    selectedVerboseHint = AnyView(Text(hint))
                    shouldDisplayHint.toggle()
                },
                label: {
                    Image(systemName: "questionmark.circle").accessibilityLabel(Text("More information"))
                }
            ).buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        List {
            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.showForecastWatch,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Show forecast on Watch")
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Show Forecast on Watch"),
                miniHint: String(localized: "Shows forecast on the Apple Watch"),
                verboseHint: Text(
                    "Enable this feature to show the forecast on the Apple Watch"
                ),
                headerText: String(localized: "Display")
            )

            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.confirmBolusFaster,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Confirm Bolus Faster")
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Confirm Bolus Faster"),
                miniHint: String(localized: "Reduce the number of crown rotations required for bolus confirmation."),
                verboseHint: Text(
                    "Enabling this feature lowers the number of turns on the crown dial required when confirming a bolus."
                ),
                headerText: String(localized: "Treatments")
            )

            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: $state.untetheredModeWatch,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Watch Mode")
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Watch Mode"),
                miniHint: String(localized: "Let the watch run the loop with its own pump and CGM connection"),
                verboseHint: Text(
                    "When this is off, neither the iPhone nor the watch starts watch mode, the watch hides its status page and the iPhone sends it no copy to start without it. A session still running hands back."
                ),
                headerText: String(localized: "Watch Mode")
            )

            if state.untetheredModeWatch {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.allowUntetheredStartWithoutPhoneWatch,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Allow Start Without iPhone")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Allow Start Without iPhone"),
                    miniHint: String(localized: "Let the watch start watch mode while the iPhone is unavailable"),
                    verboseHint: Text(
                        "For when you leave without starting watch mode. While this is on, the phone keeps a copy of your settings, carbs and doses on the watch, renewed at least every 30 minutes. With the iPhone out of reach, and that copy younger than your insulin's action time, the watch offers Start Without Phone on its watch mode page; it never starts by itself. The watch first books insulin the pod delivered that the copy doesn't know of, and the phone stops dosing as soon as it hears from the watch. When this is off, the phone sends no copy and the watch hides the button."
                    ),
                    headerText: nil
                )

                if state.allowUntetheredStartWithoutPhoneWatch {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.fallbackLoopWatch,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = String(localized: "Start by Itself When iPhone Stops")
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: String(localized: "Start by Itself When iPhone Stops"),
                        miniHint: String(localized: "The watch takes over the loop when the iPhone is gone"),
                        verboseHint: Text(
                            "Needs the Watch sensor switch on the watch (its own G7 reading). When the iPhone's newest reading the watch has is 10 minutes old, the watch looks at the pod, without dosing, and looks again about 10 minutes later. Only if nobody used the pod in between, and the iPhone's copy was at most an hour old when it went silent, does the watch start watch mode by itself from the iPhone's copy, as Start Without Phone does, about 20 minutes after the iPhone's last reading; right before its first dose it checks once more that the iPhone hasn't used the pod since. If a look shows the iPhone used the pod, the watch doesn't look again for about 10 minutes unless it hears from the iPhone, because the iPhone pauses its dosing briefly after each look. When the iPhone is back in reach for a minute, the watch hands the pump back by itself, and it lets go at once if the pod shows the iPhone has used it. Idea and design by Elias Maurer."
                        ),
                        headerText: nil
                    )
                }

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.nightscoutUploadWatch,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Upload to Nightscout From the Watch")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Upload to Nightscout From the Watch"),
                    miniHint: String(localized: "While the watch loops without the iPhone, it uploads readings and loops itself"),
                    verboseHint: Text(
                        "Needs Nightscout upload on. While watch mode runs and the iPhone is out of reach, the watch uploads its glucose readings and each loop's status (IOB, forecast, what it enacted) to Nightscout itself, so followers see them as they happen. A watch without cellular uploads only on a Wi-Fi network it knows; without one, nothing goes up until the iPhone takes the session's history after the hand-back, as when this is off. The iPhone passes the watch your Nightscout address and the API secret in the hashed form Nightscout's upload takes. Boluses and temp basals still come from the iPhone after the hand-back."
                    ),
                    headerText: nil
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.untetheredTintHomeWatch,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Tint Home Screen While Watch Loops")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Tint Home Screen While Watch Loops"),
                    miniHint: String(localized: "Color the whole home screen while the watch has the pump"),
                    verboseHint: Text(
                        "While the watch runs the loop, the home screen's background takes the watch mode color, so you see at a glance that the phone doesn't dose. When this is off, only the bar at the bottom shows it."
                    ),
                    headerText: nil
                )

                // a workout session that is discarded at the end keeps Trio running through the session
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.untetheredWorkoutWatch,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Extended Watch Mode")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Extended Watch Mode"),
                    miniHint: String(
                        localized: "More stable watch mode: a workout keeps Trio running on the watch, at a clear battery cost."
                    ),
                    verboseHint: VStack(alignment: .leading, spacing: 8) {
                        Text(
                            "When this is on, the watch runs a workout with each watch mode session, from the start to the hand-back. watchOS doesn't suspend an app with a running workout, so Trio stays awake between sensor readings: fewer readings and loops are missed, and its own checks keep running."
                        )
                        Text(
                            "The workout is discarded at the end, so it isn't saved as a workout in the Fitness app. While it runs, the watch still counts it toward the Activity rings, the Exercise minutes in particular, as with any workout. It collects only the heart rate, for the minimal screen. The first start asks on the watch for permission to use workouts and read the heart rate."
                        )
                        Text("While it runs:")
                        Text(
                            "• The watch shows the workout symbol at the top, and raising the wrist shows Trio instead of the watch face: its minimal screen, or the full app with Minimal Screen off."
                        )
                        Text(
                            "To keep the watch face instead: on the Apple Watch, open Settings → General → Return to Clock → Trio, turn on Custom, choose Always, and turn off Return to App during a session. Trio keeps running and stays awake; tap the workout symbol at the top of the watch face to open it."
                        )
                        .padding(.leading, 12)
                        Text("• The heart rate sensor runs the whole time: the watch battery drains noticeably faster.")
                        Text(
                            "• Ending the workout on the watch stops the keeping awake until the next watch mode session. Watch mode itself goes on."
                        )
                    },
                    headerText: nil
                )

                if state.untetheredWorkoutWatch {
                    Section {
                        Toggle("Minimal Screen", isOn: $state.watchGlanceEnabled)
                        if state.watchGlanceEnabled {
                            NavigationLink("Minimal Screen Layout") {
                                WatchGlanceConfigurationView(layout: $state.watchGlanceLayout)
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                    } footer: {
                        Text(
                            "While the workout runs, watchOS shows Trio instead of the watch face when the wrist comes up. With Minimal Screen on, that is a calm dark screen you arrange here; tap it for the full app. Off, it is the full app at once. The workout and the keeping awake are the same either way."
                        )
                    }
                    .listRowBackground(Color.chart)
                }

                UntetheredSettingsSection(manager: resolver.resolve(UntetheredPhoneManager.self)!)
                UntetheredActivityOfferSection()
            }

            // the watch's alarms follow Settings › Notifications › Critical Alerts (sent as useCriticalAlertsWatch)

            if state.cgmSharesWithWatch {
                Section(
                    header: Text("Glucose on the Watch"),
                    footer: hintRow(
                        miniHint: String(
                            localized: "Your watch can read your \(state.cgmName) by itself when your iPhone is out of reach."
                        ),
                        label: String(localized: "Read on Apple Watch"),
                        hint: Self.readOnWatchHint(cgmName: state.cgmName)
                    ),
                    content: {
                        HStack {
                            Text("Read on Apple Watch")
                            Spacer()
                            Text(state.watchReadsSensor ? "On" : "Off").foregroundStyle(.secondary)
                        }
                        NavigationLink(String(localized: "Open CGM Settings")) {
                            CGMSettings.RootView(
                                resolver: resolver,
                                displayClose: false,
                                bluetoothManager: resolver.resolve(BluetoothStateManager.self)!
                            )
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                ).listRowBackground(Color.chart)
            }

            Section(
                header: Text("Complication Settings"),
                content: {
                    VStack {
                        Picker("Corner Label", selection: $state.complicationCornerValue) {
                            ForEach(WatchComplicationValue.allCases) { value in
                                Text(value.displayName).tag(value)
                            }
                        }.padding(.top)
                        hintRow(
                            miniHint: String(localized: "Curved text on Trio Glucose corner slots."),
                            label: String(localized: "Corner Label"),
                            hint: Self.cornerLabelHint
                        )
                    }
                }
            ).listRowBackground(Color.chart)

            Section {
                VStack {
                    Picker("Small Line", selection: $state.complicationSecondaryValue) {
                        ForEach(WatchComplicationValue.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }.padding(.top)
                    hintRow(
                        miniHint: String(localized: "Second line on Trio Glucose, Trio Gauge and Trio Chart."),
                        label: String(localized: "Small Line"),
                        hint: Self.smallLineHint
                    )
                }
            }.listRowBackground(Color.chart)

            Section {
                VStack {
                    Stepper(
                        value: $state.complicationStaleMinutes,
                        in: WatchComplicationDefaults.staleMinutesRange,
                        step: WatchComplicationDefaults.staleMinutesStep
                    ) {
                        HStack {
                            Text("Mark Stale After")
                            Spacer()
                            Text("\(state.complicationStaleMinutes) min").foregroundStyle(.secondary)
                        }
                    }.padding(.top)
                    hintRow(
                        miniHint: String(localized: "Show -- once data is older than this. Complications can lag."),
                        label: String(localized: "Mark Stale After"),
                        hint: Self.markStaleAfterHint
                    )
                }
            }.listRowBackground(Color.chart)

            Section {
                VStack {
                    Picker("Color Mode", selection: $state.complicationColorMode) {
                        ForEach(WatchComplicationColorMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }.padding(.top)
                    hintRow(
                        miniHint: String(localized: "Glucose number in color or in white."),
                        label: String(localized: "Color Mode"),
                        hint: Self.colorModeHint
                    )
                }
            }.listRowBackground(Color.chart)

            Section {
                NavigationLink("Complication Previews") {
                    WatchComplicationPreviewsView(preview: previewState)
                }.foregroundStyle(Color.accentColor)
            }.listRowBackground(Color.chart)

            Section(
                header: Text("Contact Image"),
                footer: hintRow(
                    miniHint: String(
                        localized: "Use this if the Trio complications lag. It shows every new reading on your watch face."
                    ),
                    label: String(localized: "Contact Image"),
                    hint: Self.contactImageHint
                ),
                content: {
                    VStack {
                        HStack {
                            NavigationLink("Contacts Configuration") {
                                ContactImage.RootView(resolver: resolver)
                            }.foregroundStyle(Color.accentColor)
                        }
                    }
                }
            ).listRowBackground(Color.chart)
        }
        .listSectionSpacing(sectionSpacing)
        .contentMargins(.bottom, 40, for: .scrollContent)
        // back from the CGM's settings
        .onAppear { state.refreshWatchSensor() }
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                sheetTitle: String(localized: "Help", comment: "Help sheet title")
            )
        }
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.automatic)
        .settingsHighlightScroll()
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}

/// Arranges Extended Untethered Mode's minimal watch screen, as the Live Activity's widgets are: drag an element onto a
/// slot, tap one to add it, drag it back onto the list or tap its trash to remove it.
struct WatchGlanceConfigurationView: View {
    @Binding var layout: WatchGlanceLayout

    @State private var targetedSlot: Int?
    @State private var isPaletteTargeted = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    private static let rowHeight: CGFloat = 46
    private static let watchWidth: CGFloat = 230

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                watchPreview

                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                    Text(
                        "Drag an element onto a slot, or tap it to add it. Drag it back onto the list, or tap its trash, to remove it. Wide elements take two or three slots of their row."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(.secondary)
                .font(.footnote)

                palette(String(localized: "Middle"), items: WatchGlanceItem.centerItems)
                palette(String(localized: "Elements"), items: WatchGlanceItem.rowItems)

                Button(String(localized: "Reset to Default")) { apply { $0 = .standard } }
                    .padding(.top, 4)
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme).ignoresSafeArea())
        .navigationTitle("Minimal Screen")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - The watch

    private var watchPreview: some View {
        VStack(spacing: 6) {
            row(0)
            slotView(WatchGlanceLayout.center, item: layout.slots[WatchGlanceLayout.center])
                .frame(height: 110)
            row(1)
        }
        .padding(10)
        .frame(width: Self.watchWidth)
        .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous).stroke(Color.gray.opacity(0.5), lineWidth: 3))
        .environment(\.colorScheme, .dark)
    }

    private func row(_ index: Int) -> some View {
        let slots = WatchGlanceLayout.rows[index].count
        return GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(layout.row(index), id: \.slot) { element in
                    slotView(element.slot, item: element.item)
                        .padding(2)
                        .frame(width: geometry.size.width * CGFloat(element.item?.width ?? 1) / CGFloat(slots))
                }
            }
        }
        .frame(height: Self.rowHeight)
    }

    @ViewBuilder private func slotView(_ slot: Int, item: WatchGlanceItem?) -> some View {
        let isTargeted = targetedSlot == slot
        Group {
            if let item {
                tile(item, highlighted: isTargeted)
                    .overlay(alignment: .topTrailing) {
                        Button { apply { $0.clear(slot) } } label: {
                            Image(systemName: "trash.circle.fill")
                                .foregroundColor(Color(UIColor.systemGray2))
                                .background(Circle().fill(Color.white))
                                .font(.body)
                        }
                        .offset(x: 6, y: -6)
                        .accessibilityLabel(Text("Remove \(item.label)"))
                    }
                    .draggable(item) { tile(item).frame(width: 70, height: Self.rowHeight) }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [4]))
                    .foregroundColor(isTargeted ? Color.accentColor : Color.gray)
                    .overlay(Image(systemName: "plus").foregroundColor(.secondary))
                    .accessibilityLabel(Text("Empty slot"))
            }
        }
        .dropDestination(for: WatchGlanceItem.self) { dropped, _ in
            targetedSlot = nil
            guard let item = dropped.first else { return false }
            var placed = false
            apply { placed = $0.place(item, at: slot) }
            return placed
        } isTargeted: { hovering in
            if hovering { targetedSlot = slot } else if targetedSlot == slot { targetedSlot = nil }
        }
    }

    private func tile(_ item: WatchGlanceItem, highlighted: Bool = false) -> some View {
        sample(item)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(highlighted ? Color.accentColor : Color.gray.opacity(0.6), lineWidth: highlighted ? 2 : 1)
            )
    }

    // MARK: - Palette

    private func palette(_ title: String, items: [WatchGlanceItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).foregroundColor(.secondary).font(.footnote)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                ForEach(items, id: \.self) { item in
                    paletteCell(item)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(isPaletteTargeted ? 0.25 : 0.1)))
        .dropDestination(for: WatchGlanceItem.self) { dropped, _ in
            isPaletteTargeted = false
            guard let item = dropped.first, layout.slots.contains(item) else { return false }
            apply { $0.remove(item) }
            return true
        } isTargeted: { isPaletteTargeted = $0 }
    }

    private func paletteCell(_ item: WatchGlanceItem) -> some View {
        let isPlaced = layout.slots.contains(item)
        return VStack(spacing: 4) {
            tile(item)
                .frame(height: Self.rowHeight)
                .environment(\.colorScheme, .dark)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
            Text(item.label + (item.width > 1 ? " (\(item.width)×)" : ""))
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(isPlaced ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if !isPlaced { apply { $0.placeInFirstFreeSlot(item) } } }
        .draggable(item) { tile(item).frame(width: 70, height: Self.rowHeight) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(isPlaced ? "Already on the screen" : "Adds this element to the screen"))
    }

    // MARK: - Samples

    @ViewBuilder private func sample(_ item: WatchGlanceItem) -> some View {
        switch item {
        case .glucoseLarge:
            Text("123 →").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Color.loopGreen)
        case .glucoseChart:
            VStack(spacing: 2) {
                Text("123 →").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(Color.loopGreen)
                chartSample
            }
        case .chart:
            chartSample
        default:
            HStack(spacing: 4) {
                ForEach(item.parts, id: \.self) { part in
                    VStack(spacing: 0) {
                        partSample(part).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(part.label.uppercased()).font(.system(size: 7, weight: .medium)).foregroundStyle(.gray)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder private func partSample(_ item: WatchGlanceItem) -> some View {
        switch item {
        case .glucose: Text("123→").foregroundStyle(Color.loopGreen)
        case .loop:
            HStack(spacing: 2) {
                Circle().stroke(Color.loopGreen, lineWidth: 2).frame(width: 9, height: 9)
                Text("2m")
            }
        case .iob: Text("1.25").foregroundStyle(Color.insulin)
        case .cob: Text("24").foregroundStyle(Color.orange)
        case .tempBasal: Text("0.85")
        case .eventualGlucose: Text("108")
        case .heartRate:
            HStack(spacing: 1) {
                Image(systemName: "heart.fill").font(.system(size: 8)).foregroundStyle(Color.red)
                Text("72")
            }
        case .reservoir: Text("86 U")
        case .lastReading: Text("1m")
        case .totalDailyDose: Text("38.4 U")
        case .clock: Text("12:05")
        default: Text("")
        }
    }

    private var chartSample: some View {
        Image(systemName: "chart.dots.scatter")
            .font(.system(size: 26))
            .foregroundStyle(Color.loopGreen, Color.cyan.opacity(0.6))
    }

    // MARK: - Changes

    private func apply(_ change: (inout WatchGlanceLayout) -> Void) {
        var changed = layout
        change(&changed)
        guard changed != layout else { return }
        withAnimation(.easeInOut(duration: 0.2)) { layout = changed }
    }
}

extension WatchGlanceItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

private struct WatchComplicationPreviewsView: View {
    let preview: ComplicationState

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        List {
            Section(
                footer: Text(
                    "Previews use sample data in your units and follow your complication settings. Add them from the watch face editor under Trio. Corner slots curve the label round the face."
                ),
                content: {
                    ForEach(ComplicationKind.allCases) { kind in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(kind.displayName).font(.headline)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(kind.slots.filter { $0 != .inline }, id: \.self) { slot in
                                        ComplicationPreview(kind: kind, slot: slot, state: preview)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            Text(kind.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            ).listRowBackground(Color.chart)
        }
        .navigationTitle("Complication Previews")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
    }
}
