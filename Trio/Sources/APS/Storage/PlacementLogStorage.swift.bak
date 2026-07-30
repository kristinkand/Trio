import CoreData
import Foundation
import Swinject

protocol PlacementLogStorage {
    func addPlacementLog(
        deviceType: PlacementDeviceType,
        location: PlacementLocation,
        hasSiteIssue: Bool,
        isPainful: Bool
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
    ///   - isPainful: Whether the placement was painful.
    func addPlacementLog(
        deviceType: PlacementDeviceType,
        location: PlacementLocation,
        hasSiteIssue: Bool,
        isPainful: Bool
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

    /// Deletes a placement log entry from Core Data.
    ///
    /// - Parameter objectID: The `NSManagedObjectID` of the object to delete.
    func deletePlacementLog(_ objectID: NSManagedObjectID) async {
        await CoreDataStack.shared.deleteObject(identifiedBy: objectID)
    }
}
