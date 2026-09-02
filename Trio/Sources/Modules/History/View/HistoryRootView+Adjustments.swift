import CoreData
import SwiftUI

extension History.RootView {
    var adjustmentsList: some View {
        List {
            HStack {
                Text("Adjustment").foregroundStyle(.secondary)
                Spacer()
            }
            if !combinedAdjustments.isEmpty {
                ForEach(combinedAdjustments) { item in
                    adjustmentView(for: item)
                }
            } else {
                ContentUnavailableView(
                    String(localized: "No data."),
                    systemImage: "clock.arrow.2.circlepath"
                )
            }
        }
        .listRowBackground(Color.chart)
    }

    fileprivate var combinedAdjustments: [AdjustmentItem] {
        let overrides = overrideRunStored.map { override -> AdjustmentItem in
            AdjustmentItem(
                id: override.objectID,
                name: override.name ?? String(localized: "Override"),
                startDate: override.startDate ?? Date(),
                endDate: override.endDate ?? Date(),
                target: override.target?.decimalValue,
                type: .override
            )
        }

        let tempTargets = tempTargetRunStored.map { tempTarget -> AdjustmentItem in
            AdjustmentItem(
                id: tempTarget.objectID,
                name: tempTarget.name ?? String(localized: "Temp Target"),
                startDate: tempTarget.startDate ?? Date(),
                endDate: tempTarget.endDate ?? Date(),
                target: tempTarget.target?.decimalValue,
                type: .tempTarget
            )
        }

        let combined = overrides + tempTargets + weekendProfileAdjustments
        return combined.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate > $1.endDate
            }
            return $0.startDate > $1.startDate
        }
    }

    /// Weekend Profile has no Core Data record the way Overrides/Temp Targets do (see
    /// `WeekendProfileStore`), so it's anchored here from its own lightweight run history instead of
    /// a `@FetchRequest`. Mirrors `overridesRunStoredFromOneDayAgo`/`tempTargetRunStoredFromOneDayAgo`
    /// by only surfacing runs that overlap the last 24h, and appends a synthetic "still running"
    /// entry (ending "now") while Weekend Profile is currently active so it's anchored here exactly
    /// like an in-progress Override or Temp Target already is.
    fileprivate var weekendProfileAdjustments: [AdjustmentItem] {
        let cutoff = Date.oneDayAgo
        var items = WeekendProfileStore.runHistory
            .filter { $0.endDate >= cutoff }
            .map { run -> AdjustmentItem in
                AdjustmentItem(
                    id: AnyHashable(run.id),
                    name: run.name,
                    startDate: run.startDate,
                    endDate: run.endDate,
                    target: nil,
                    type: .weekendProfile
                )
            }

        if WeekendProfileStore.isActive, let start = WeekendProfileStore.activeStartDate {
            items.append(
                AdjustmentItem(
                    id: AnyHashable("weekendProfileActiveRun"),
                    name: WeekendProfileStore.name,
                    startDate: start,
                    endDate: Date(),
                    target: nil,
                    type: .weekendProfile
                )
            )
        }
        return items
    }

    fileprivate struct AdjustmentItem: Identifiable {
        let id: AnyHashable
        let name: String
        let startDate: Date
        let endDate: Date
        let target: Decimal?
        let type: AdjustmentType
    }

    fileprivate enum AdjustmentType {
        case override
        case tempTarget
        case weekendProfile

        var symbolName: String {
            switch self {
            case .override:
                return "clock.arrow.2.circlepath"
            case .tempTarget:
                return "target"
            case .weekendProfile:
                // Matches the icon used for the Weekend Profile indicator elsewhere in the app
                // (see HomeRootView+BottomControls.swift).
                return "sun.max.fill"
            }
        }

        var symbolColor: Color {
            switch self {
            case .override:
                return .purple
            case .tempTarget:
                return .green
            case .weekendProfile:
                // Matches the color used for the Weekend Profile indicator elsewhere in the app
                // (see HomeRootView+BottomControls.swift).
                return .mint
            }
        }
    }

    @ViewBuilder fileprivate func adjustmentView(for item: AdjustmentItem) -> some View {
        let formattedDates =
            "\(Formatter.dateFormatter.string(from: item.startDate)) - \(Formatter.dateFormatter.string(from: item.endDate))"

        let targetDescription: String = {
            guard let target = item.target, target != 0 else {
                return ""
            }
            return "\(state.units == .mgdL ? target : target.asMmolL) \(state.units.rawValue)"
        }()

        let labels: [String] = [
            targetDescription,
            formattedDates
        ].filter { !$0.isEmpty }

        ZStack(alignment: .trailing) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: item.type.symbolName)
                            .foregroundStyle(item.type.symbolColor)
                        Text(item.name)
                            .font(.headline)
                        Spacer()
                    }
                    HStack(spacing: 5) {
                        ForEach(labels, id: \.self) { label in
                            Text(label)
                            if label != labels.last {
                                Divider()
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
                .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 8)
    }
}
