import Foundation

// Ids are UUIDs, as the TypeScript `RecipeId` and friends were branded UUID strings. The
// aliases name what an id is for; SwiftData models store them as plain `UUID` attributes.

public typealias RecipeId = UUID
public typealias TagId = UUID
public typealias PlanEntryId = UUID
public typealias DiaryEntryId = UUID
public typealias FavouriteId = UUID
public typealias GatherItemId = UUID
public typealias ImportId = UUID
