import CoreData
import Foundation

public extension PlacementLogStored {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PlacementLogStored> {
        NSFetchRequest<PlacementLogStored>(entityName: "PlacementLogStored")
    }

    @NSManaged var id: UUID?
    @NSManaged var date: Date?
    @NSManaged var deviceType: String?
    @NSManaged var location: String?
    @NSManaged var hasSiteIssue: Bool
    @NSManaged var hasInaccurateReadings: Bool
    @NSManaged var isPainful: Bool
    @NSManaged var isPainfulGivingInsulin: Bool
}

extension PlacementLogStored: Identifiable {}
