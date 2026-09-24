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

    // MARK: - Ending a run (see WeekendProfileStore.indefinite/durationMinutes/useSpecificDate/scheduledEndDate)

    /// Which of the three ways to end a run is currently selected, *while inactive*. There's no
    /// separate "Start" tap -- picking a mode (and, for the latter two, actually dialing in a
    /// value) starts the run immediately via `startProfile(...)`, which also flips `isActive` to
    /// `true` itself. Once active, this only reflects how the run that's already going was
    /// started -- see the read-only "Ends" row below instead.
    private enum EndMode: Hashable {
        case indefinite, duration, specificDate
    }

    @State private var endMode: EndMode = WeekendProfileStore.indefinite
        ? .indefinite
        : (WeekendProfileStore.useSpecificDate ? .specificDate : .duration)
    @State private var weekendDurationMinutes = WeekendProfileStore.durationMinutes
    @State private var displayPickerDuration = false
    @State private var durationHours = 0
    @State private var durationMinutesPicker = 0
    /// Defaults to an hour from now rather than "now" so the DatePicker doesn't open already
    /// showing a moment that's about to be in the past.
    @State private var scheduledEndDate = WeekendProfileStore.scheduledEndDate ?? Date().addingTimeInterval(1.hours.timeInterval)

    /// Set right before `startProfile(...)` (or an external expiry) assigns `isActive` itself, so
    /// the Toggle's own `onChange(of: isActive)` -- which exists for the *user tapping the toggle
    /// directly to stop an active run* -- can tell "I did this assignment on purpose, the
    /// start/stop work is already done" apart from "the user just tapped the switch" and skip
    /// redoing that work a second time.
    @State private var isActiveChangeIsProgrammatic = false

    /// Finest raw step (1 mg/dL) in both unit systems -- matches the finest option Trio's own
    /// Override/Temp Target target pickers offer, instead of the coarse default (5 mg/dL / 9 raw
    /// units, ~0.5 mmol/L) they start with. Fixes the "can only change in 0.5 mmol/L jumps" issue.
    private var targetStep: Double { 1 }

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

    /// Starts a run right now, persisting the chosen end condition and flipping `isActive` to
    /// `true` -- the single place any of the three "pick indefinite / dial a duration / pick a
    /// date" controls below actually cause anything to start. Refuses to start a `.duration` run
    /// with no duration dialed in yet, or a `.specificDate` run whose picked moment has already
    /// passed (belt-and-suspenders with the DatePicker's own `in: Date()...`, for the gap between
    /// picking a date and this actually running) -- in both cases this simply does nothing rather
    /// than guessing at a fallback, since nothing meaningful was actually chosen yet.
    private func startProfile(mode: EndMode, durationMinutes: Decimal = 0, specificDate: Date? = nil) {
        switch mode {
        case .duration: guard durationMinutes > 0 else { return }
        case .specificDate: guard let specificDate, specificDate > Date() else { return }
        case .indefinite: break
        }

        endMode = mode
        if mode == .duration { weekendDurationMinutes = durationMinutes }
        if mode == .specificDate, let specificDate { scheduledEndDate = specificDate }

        WeekendProfileStore.indefinite = mode == .indefinite
        WeekendProfileStore.useSpecificDate = mode == .specificDate
        WeekendProfileStore.durationMinutes = mode == .duration ? durationMinutes : 0
        WeekendProfileStore.scheduledEndDate = mode == .specificDate ? specificDate : nil
        WeekendProfileStore.isActive = true

        // Only when this is the thing actually flipping `isActive` -- i.e. every call site
        // *except* the Toggle-tapped-directly path, where `isActive` is already `true` by the
        // time this runs (the Toggle's own binding sets it before onChange fires, and that
        // onChange is what called us). Setting the guard flag here in that case would never get
        // consumed (assigning `true` to something already `true` doesn't re-fire onChange), and
        // it'd wrongly swallow the *next* real stop.
        if !isActive {
            isActiveChangeIsProgrammatic = true
            isActive = true
        }
        state.startWeekendProfile()
        Foundation.NotificationCenter.default.post(name: .didUpdateWeekendProfileConfiguration, object: nil)
    }

    /// Checked on a foreground timer (see `body`) and on appear, independent of whether a real
    /// loop cycle has landed -- `Home.StateModel.updateEnactedDeterminationFromController` does
    /// the same check off the loop cycle signal for background reliability, but that signal can be
    /// slow to arrive (or never arrive, e.g. while bench-testing without live CGM data actually
    /// driving loop cycles), which left this screen's toggle looking stuck on well past the chosen
    /// end time. Dosing safety was never affected by that gap -- `OpenAPS.swift` checks
    /// `WeekendProfileStore.isExpired` directly and independently -- this only closes the gap
    /// between "stopped affecting dosing" and "the toggle/Nightscout/History visibly agree."
    private func checkForExpiry() {
        guard isActive, WeekendProfileStore.expireIfNeeded(nightscoutManager: state.nightscoutManager) else { return }
        isActiveChangeIsProgrammatic = true
        isActive = false
        Foundation.NotificationCenter.default.post(name: .didUpdateWeekendProfileConfiguration, object: nil)
    }

    /// Catches this screen's own `isActive` up with `WeekendProfileStore`'s ground truth.
    /// `checkForExpiry()` above only ever turns a run off because *time* ran out; it says nothing
    /// about a stop (or start) that happened on another screen entirely -- e.g. the Home screen's
    /// bottom-bar toggle -- which reaches this screen only via the one-shot
    /// `.didUpdateWeekendProfileConfiguration` notification. That notification has no replay, so a
    /// miss (plausible mid screen-transition) leaves `isActive` stale here until something else
    /// happens to correct it. Reconciling against the store directly on every appearance and timer
    /// tick closes that gap -- mirrors the same fix applied to HomeRootView's own indicator.
    private func resyncActiveState() {
        let storeIsActive = WeekendProfileStore.isActive
        guard isActive != storeIsActive else { return }
        isActiveChangeIsProgrammatic = true
        isActive = storeIsActive
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
            name: trimmedName.isEmpty ? "Profile" : trimmedName,
            target: overrideTarget ? target : 0,
            smbMinutes: smbMinutes,
            uamMinutes: uamMinutes,
            basalProfile: basalProfile,
            insulinSensitivities: insulinSensitivities
        )
        justSaved = true
    }

    private var displayName: String { name.isEmpty ? "Profile" : name }

    private var infoText: String {
        "A name, target, SMB/UAM minutes, and its own basal + ISF schedule, that you start yourself, independent of Overrides -- meant for stretches like a weekend or vacation. Runs until you stop it, or optionally ends on its own -- either after a duration or at a specific date & time you set before starting it. Carb ratio is never changed -- it always comes from your normal settings. If a real Override or Temp Target is running, it fully takes over the dosing math and Profile is paused until it ends."
    }

    var body: some View {
        Section {
            HStack {
                if isActive {
                    HStack(spacing: 4) {
                        TextField("Profile", text: $name)
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
                        // Both `startProfile(...)` above and `checkForExpiry()` below set this
                        // flag right before assigning `isActive` themselves -- when that's why
                        // we're here, the real work (persisting the store, Nightscout, History,
                        // the notification) is already done, so there's nothing left to do.
                        guard !isActiveChangeIsProgrammatic else {
                            isActiveChangeIsProgrammatic = false
                            return
                        }
                        if isActive {
                            // Reachable only by tapping the switch directly without having gone
                            // through any of the End controls below -- treat that the same as
                            // explicitly choosing Indefinite.
                            startProfile(mode: .indefinite)
                        } else {
                            WeekendProfileStore.isActive = false
                            state.stopWeekendProfile()
                            Foundation.NotificationCenter.default.post(name: .didUpdateWeekendProfileConfiguration, object: nil)
                        }
                    }
            }

            if !isActive {
                Picker("End", selection: $endMode) {
                    Text("Indefinite").tag(EndMode.indefinite)
                    Text("Duration").tag(EndMode.duration)
                    Text("Date & Time").tag(EndMode.specificDate)
                }
                .pickerStyle(.segmented)
                .onChange(of: endMode) {
                    switch endMode {
                    case .indefinite:
                        // A complete, unambiguous choice on its own -- start right away.
                        startProfile(mode: .indefinite)
                    case .duration:
                        // If a duration's already dialed in from last time, reuse it immediately
                        // rather than making you re-touch the wheel just to confirm the same
                        // number. A never-configured 0 waits for an actual pick below instead.
                        if weekendDurationMinutes > 0 {
                            startProfile(mode: .duration, durationMinutes: weekendDurationMinutes)
                        }
                    case .specificDate:
                        // Not reused the same way -- the prefilled default is always "an hour from
                        // right now," which isn't a real preference to fall back to, so this
                        // always waits for an explicit pick below.
                        break
                    }
                }

                if endMode == .specificDate {
                    // `in: Date()...` keeps the picker itself from offering an already-past
                    // moment. Starts the moment you actually change the value -- not on first
                    // appearing with its prefilled default, since `onChange` only fires on a real
                    // change, not on the initial assignment.
                    DatePicker(
                        "Ends",
                        selection: $scheduledEndDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .onChange(of: scheduledEndDate) {
                        startProfile(mode: .specificDate, specificDate: scheduledEndDate)
                    }
                } else if endMode == .duration {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(state.formatHoursAndMinutes(Int(weekendDurationMinutes)))
                            .foregroundColor(!displayPickerDuration ? .primary : .accentColor)
                            .onTapGesture {
                                displayPickerDuration.toggle()
                            }
                    }

                    if displayPickerDuration {
                        HStack {
                            Picker("Hours", selection: $durationHours) {
                                ForEach(0 ..< 97) { hour in
                                    Text("\(hour) hr").tag(hour)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                            .onChange(of: durationHours) {
                                let minutes = state.convertToMinutes(durationHours, durationMinutesPicker)
                                startProfile(mode: .duration, durationMinutes: minutes)
                            }

                            Picker("Minutes", selection: $durationMinutesPicker) {
                                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                            .onChange(of: durationMinutesPicker) {
                                let minutes = state.convertToMinutes(durationHours, durationMinutesPicker)
                                startProfile(mode: .duration, durationMinutes: minutes)
                            }
                        }
                        .listRowSeparator(.hidden, edges: .top)
                    }
                }
            } else if !WeekendProfileStore.indefinite, let end = WeekendProfileStore.activeEndDate {
                HStack {
                    Text("Ends")
                    Spacer()
                    // Full date + time, not just time -- a specific-date run can end days out, so
                    // "8:00 PM" alone would be ambiguous about which day.
                    Text(end.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
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
        .onAppear {
            loadDraftIfNeeded()
            checkForExpiry()
            resyncActiveState()
        }
        // Foreground-only, and deliberately not the only thing keeping a timed run honest --
        // see `checkForExpiry`'s doc comment for how this relates to dosing safety and to the
        // loop-cycle-driven check in Home.StateModel. This just makes an expired run's toggle
        // catch up promptly while this screen happens to be open and watched, e.g. while testing.
        // `resyncActiveState()` alongside it catches a stop/start made elsewhere, not just one
        // caused by time running out -- see its own doc comment.
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
            checkForExpiry()
            resyncActiveState()
        }

        if isActive {
            WeekendScheduleEditor(
                title: "\(displayName) Basal",
                footer: "Absolute basal rates, same as the real Basal Profile Editor. Only used while Profile is active.",
                tint: .mint,
                valueValues: state.weekendBasalRateValues,
                valueLabel: basalLabel,
                initialEntries: basalEntries,
                onChange: { basalEntries = $0; justSaved = false }
            )

            WeekendScheduleEditor(
                title: "\(displayName) ISF",
                footer: "Absolute insulin sensitivities, same as the real ISF Editor. Only used while Profile is active.",
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
