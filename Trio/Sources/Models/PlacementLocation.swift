import Foundation

enum PlacementDeviceType: String, CaseIterable, Identifiable, Codable {
    case pump
    case sensor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pump: return String(localized: "Pump", comment: "Placement device type")
        case .sensor: return String(localized: "Sensor", comment: "Placement device type")
        }
    }
}

enum PlacementBodyRegion: String, CaseIterable, Identifiable {
    case upperArm
    case abdomen
    case buttocks
    case thigh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .upperArm: return String(localized: "Upper Arm", comment: "Placement body region")
        case .abdomen: return String(localized: "Abdomen", comment: "Placement body region")
        case .buttocks: return String(localized: "Buttocks", comment: "Placement body region")
        case .thigh: return String(localized: "Thigh", comment: "Placement body region")
        }
    }
}

enum PlacementLocation: String, CaseIterable, Identifiable, Codable {
    case upperArmLeft
    case upperArmRight
    case abdomenLeftHigh
    case abdomenLeftLow
    case abdomenRightHigh
    case abdomenRightLow
    /// Sensor-only abdomen placement. Unlike the four pump abdomen quadrants above, sensors don't
    /// need that level of rotation detail, so this is a single, undivided "Abdomen" option.
    case abdomenSensor
    case buttockLeftHigh
    case buttockLeftLow
    case buttockRightHigh
    case buttockRightLow
    case thighLeftTop
    case thighLeftInner
    case thighLeftOuter
    case thighRightTop
    case thighRightInner
    case thighRightOuter

    var id: String { rawValue }

    var region: PlacementBodyRegion {
        switch self {
        case .upperArmLeft,
             .upperArmRight:
            return .upperArm
        case .abdomenLeftHigh,
             .abdomenLeftLow,
             .abdomenRightHigh,
             .abdomenRightLow,
             .abdomenSensor:
            return .abdomen
        case .buttockLeftHigh,
             .buttockLeftLow,
             .buttockRightHigh,
             .buttockRightLow:
            return .buttocks
        case .thighLeftInner,
             .thighLeftOuter,
             .thighLeftTop,
             .thighRightInner,
             .thighRightOuter,
             .thighRightTop:
            return .thigh
        }
    }

    var displayName: String {
        switch self {
        case .upperArmLeft: return String(localized: "Left", comment: "Placement location")
        case .upperArmRight: return String(localized: "Right", comment: "Placement location")
        case .abdomenLeftHigh: return String(localized: "Left High", comment: "Placement location")
        case .abdomenLeftLow: return String(localized: "Left Low", comment: "Placement location")
        case .abdomenRightHigh: return String(localized: "Right High", comment: "Placement location")
        case .abdomenRightLow: return String(localized: "Right Low", comment: "Placement location")
        case .abdomenSensor: return String(localized: "Abdomen", comment: "Placement location")
        case .buttockLeftHigh: return String(localized: "Left High", comment: "Placement location")
        case .buttockLeftLow: return String(localized: "Left Low", comment: "Placement location")
        case .buttockRightHigh: return String(localized: "Right High", comment: "Placement location")
        case .buttockRightLow: return String(localized: "Right Low", comment: "Placement location")
        case .thighLeftTop: return String(localized: "Left Top", comment: "Placement location")
        case .thighLeftInner: return String(localized: "Left Inner", comment: "Placement location")
        case .thighLeftOuter: return String(localized: "Left Outer", comment: "Placement location")
        case .thighRightTop: return String(localized: "Right Top", comment: "Placement location")
        case .thighRightInner: return String(localized: "Right Inner", comment: "Placement location")
        case .thighRightOuter: return String(localized: "Right Outer", comment: "Placement location")
        }
    }

    /// Full name including region, e.g. "Abdomen \u00b7 Left High" -- used in list rows.
    /// `.abdomenSensor` has no sub-location of its own, so it's shown as plain "Abdomen" rather
    /// than the redundant "Abdomen · Abdomen".
    var fullDisplayName: String {
        self == .abdomenSensor ? region.displayName : "\(region.displayName) · \(displayName)"
    }

    /// Which device type(s) this specific location applies to. Almost every location applies to
    /// both pump and sensor placements; the two exceptions are the detailed pump abdomen quadrants
    /// (pump only) and the simplified `.abdomenSensor` entry (sensor only) that replaces them.
    var deviceTypes: Set<PlacementDeviceType> {
        switch self {
        case .abdomenLeftHigh,
             .abdomenLeftLow,
             .abdomenRightHigh,
             .abdomenRightLow:
            return [.pump]
        case .abdomenSensor:
            return [.sensor]
        default:
            return [.pump, .sensor]
        }
    }

    static func locations(in region: PlacementBodyRegion, for deviceType: PlacementDeviceType) -> [PlacementLocation] {
        allCases.filter { $0.region == region && $0.deviceTypes.contains(deviceType) }
    }
}
