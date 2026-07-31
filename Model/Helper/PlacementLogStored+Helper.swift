import CoreData
import Foundation

extension NSPredicate {
    static var allPlacementLogs: NSPredicate {
        NSPredicate(format: "date >= %@", Date.sixMonthsAgo as NSDate)
    }
}

extension PlacementLogStored {
    /// Typed access to the raw `deviceType` string; falls back to `.pump` if unset/unrecognized
    /// (should never happen for entries created through the app's own add flow).
    var deviceTypeEnum: PlacementDeviceType {
        get { PlacementDeviceType(rawValue: deviceType ?? "") ?? .pump }
        set { deviceType = newValue.rawValue }
    }

    /// Typed access to the raw `location` string; falls back to `.abdomenLeftHigh` if unset/unrecognized.
    var locationEnum: PlacementLocation {
        get { PlacementLocation(rawValue: location ?? "") ?? .abdomenLeftHigh }
        set { location = newValue.rawValue }
    }

    static func fetch(
        _ predicate: NSPredicate,
        ascending: Bool = false,
        fetchLimit: Int? = nil
    ) -> NSFetchRequest<PlacementLogStored> {
        let request = PlacementLogStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: ascending)]
        request.predicate = predicate
        if let fetchLimit = fetchLimit {
            request.fetchLimit = fetchLimit
        }
        return request
    }
}
