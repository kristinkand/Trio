extension Adjustments {
    final class Provider: BaseProvider, AdjustmentsProvider {
        func getBGTargets() async -> BGTargets {
            await storage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        }

        /// The real (non-Weekend) basal schedule -- used only to prefill Weekend Profile's own
        /// schedule the first time someone opens the editor, so they start from a sensible copy of
        /// their actual settings instead of an empty list. Same lookup `BasalProfileEditorProvider`
        /// uses for the real editor.
        var currentBasalProfile: [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
                ?? []
        }

        /// The real (non-Weekend) ISF schedule -- same prefill purpose as `currentBasalProfile`.
        /// Same lookup `ISFEditorProvider` uses for the real editor.
        var currentInsulinSensitivities: InsulinSensitivities {
            storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                ?? InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: [])
        }
    }
}
