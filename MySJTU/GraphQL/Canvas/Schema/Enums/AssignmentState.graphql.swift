// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

extension CanvasSchema {
  /// States that an Assignment can be in
  enum AssignmentState: String, EnumType {
    case unpublished = "unpublished"
    case published = "published"
    case deleted = "deleted"
    case duplicating = "duplicating"
    case failedToDuplicate = "failed_to_duplicate"
    case importing = "importing"
    case failToImport = "fail_to_import"
    case migrating = "migrating"
    case failedToMigrate = "failed_to_migrate"
  }

}