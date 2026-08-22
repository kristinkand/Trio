import CoreData
import Foundation
import Swinject

protocol PlacementLogStorage {
    func addPlacementLog(
        deviceType: PlacementDeviceType,
        location: PlacementLocation,
        hasSiteIssue: Bool,
        isPainful: Bool,
        isPainfulGivingInsulin: Bool,
        hasInaccurateReadings: Bool
    ) async
    func updatePlacementLog(
        _ objectID: NSManagedObjectID,
        deviceType: PlacementDeviceType,
        location: PlacementLocation,
        hasSiteIssue: Bool,
        isPainful: Bool,
        isPainfulGivingInsulin: Bool,
        hasInaccurateReadings: Bool
    ) async
    func deletePlacementLog(_ objectID: NSManagedObjectID) async
}

final class BasePlacementLogStorage: PlacementLogStorage, Injectable {
    private let makeContext: () -> NSManagedObjectContext

    init(resolver: Resolver, contextProvider: (() -> NSManagedObjectContext)? = nil) {
        makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
        injectServices(resolver)
    }

    /// Stores a new pump/sensor placement log entry.
    ///
    /// - Parameters:
    ///   - deviceType: Whether this entry is for a pump or a sensor.
    ///   - location: The body location the device was placed at.
    ///   - hasSiteIssue: Whether a site issue was noted for this placement.
    ///   - isPainful: Whether the placement was painful to wear.
    ///   - isPainfulGivingInsulin: Whether giving insulin at this site was painful (pump only).
    ///   - hasInaccurateReadings: Whether this sensor placement produced inaccurate readings (sensor only).
    func addPlacementLog(
        deviceType: PlacementDeviceType,
        location: PlacementLocation,
        hasSiteIssue: Bool,
        isPainful: Bool,
        isPainfulGivingInsulin: Bool,
        hasInaccurateReadings: Bool
    ) async {
        let context = makeContext()
        context.name = "addPlacementLog"
        await context.perform {
            let newEntry = PlacementLogStored(context: context)
            newEntry.id = UUID()
            newEntry.date = Date()
            newEntry.deviceTypeEnum = deviceType
            newEntry.locationEnum = location
            newEntry.hasSiteIssue = hasSiteIssue
            newEntry.isPainful = isPainful
            newEntry.isPainfulGivingInsulin = isPainfulGivingInsulin
            newEntry.hasInaccurateReadings = hasInaccurateReadings

            do {
                guard context.hasChanges else { return }
                try context.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Placement Log Entry to Core Data with error: \(error.userInfo)"
                )
            }
        }
    }

    /// Updates an existing pump/sensor placement log entry.
    ///
    /// - Parameters:
    ///   - objectID: The `NSManagedObjectID` of the entry to update.
    ///   - deviceType: Whether this entry is for a pump or a sensor.
    ///   - location: The body location the device was placed at.
    ///   - hasSiteIssue: Whether a site issue was noted for this placement.
    ///   - isPainful: Whether the placement was painful to wear.
    ///   - isPainfulGivingInsulin: Whether giving insulin at this site was painful (pump only).
    ///   - hasInaccurateReadings: Whether this sensor placement produced inaccurate readings (sensor only).
    func updatePlacementLog(
        _ objectID: NSManagedObjectID,
        deviceType: PlacementDeviceType,
        location: PlacementLocation,
        hasSiteIssue: Bool,
        isPainful: Bool,
        isPainfulGivingInsulin: Bool,
        hasInaccurateReadings: Bool
    ) async {
        let context = makeContext()
        context.name = "updatePlacementLog"
        await context.perform {
            guard let entry = try? context.existingObject(with: objectID) as? PlacementLogStored else {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to find Placement Log Entry to update."
                )
                return
            }
            entry.deviceTypeEnum = deviceType
            entry.locationEnum = location
            entry.hasSiteIssue = hasSiteIssue
            entry.isPainful = isPainful
            entry.isPainfulGivingInsulin = isPainfulGivingInsulin
            entry.hasInaccurateReadings = hasInaccurateReadings

            do {
                guard context.hasChanges else { return }
                try context.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update Placement Log Entry in Core Data with error: \(error.userInfo)"
                )
            }
        }
    }

    /// Deletes a placement log entry from Core Data.
    ///
    /// - Parameter objectID: The `NSManagedObjectID` of the object to delete.
    func deletePlacementLog(_ objectID: NSManagedObjectID) async {
        await CoreDataStack.shared.deleteObject(identifiedBy: objectID)
    }
}
