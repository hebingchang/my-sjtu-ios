// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

protocol CanvasSchema_SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == CanvasSchema.SchemaMetadata {}

protocol CanvasSchema_InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == CanvasSchema.SchemaMetadata {}

protocol CanvasSchema_MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == CanvasSchema.SchemaMetadata {}

protocol CanvasSchema_MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == CanvasSchema.SchemaMetadata {}

extension CanvasSchema {
  typealias SelectionSet = CanvasSchema_SelectionSet

  typealias InlineFragment = CanvasSchema_InlineFragment

  typealias MutableSelectionSet = CanvasSchema_MutableSelectionSet

  typealias MutableInlineFragment = CanvasSchema_MutableInlineFragment

  enum SchemaMetadata: ApolloAPI.SchemaMetadata {
    static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

    static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
      switch typename {
      case "Account": return CanvasSchema.Objects.Account
      case "AssessmentRequest": return CanvasSchema.Objects.AssessmentRequest
      case "Assignment": return CanvasSchema.Objects.Assignment
      case "AssignmentConnection": return CanvasSchema.Objects.AssignmentConnection
      case "AssignmentGroup": return CanvasSchema.Objects.AssignmentGroup
      case "AssignmentOverride": return CanvasSchema.Objects.AssignmentOverride
      case "CommentBankItem": return CanvasSchema.Objects.CommentBankItem
      case "CommunicationChannel": return CanvasSchema.Objects.CommunicationChannel
      case "ContentTag": return CanvasSchema.Objects.ContentTag
      case "Conversation": return CanvasSchema.Objects.Conversation
      case "Course": return CanvasSchema.Objects.Course
      case "Discussion": return CanvasSchema.Objects.Discussion
      case "DiscussionEntry": return CanvasSchema.Objects.DiscussionEntry
      case "DiscussionEntryDraft": return CanvasSchema.Objects.DiscussionEntryDraft
      case "Enrollment": return CanvasSchema.Objects.Enrollment
      case "ExternalTool": return CanvasSchema.Objects.ExternalTool
      case "ExternalUrl": return CanvasSchema.Objects.ExternalUrl
      case "File": return CanvasSchema.Objects.File
      case "GradingPeriod": return CanvasSchema.Objects.GradingPeriod
      case "Group": return CanvasSchema.Objects.Group
      case "GroupMembership": return CanvasSchema.Objects.GroupMembership
      case "GroupSet": return CanvasSchema.Objects.GroupSet
      case "InternalSetting": return CanvasSchema.Objects.InternalSetting
      case "LearningOutcome": return CanvasSchema.Objects.LearningOutcome
      case "LearningOutcomeGroup": return CanvasSchema.Objects.LearningOutcomeGroup
      case "MediaObject": return CanvasSchema.Objects.MediaObject
      case "MediaTrack": return CanvasSchema.Objects.MediaTrack
      case "MessageableContext": return CanvasSchema.Objects.MessageableContext
      case "MessageableUser": return CanvasSchema.Objects.MessageableUser
      case "Module": return CanvasSchema.Objects.Module
      case "ModuleExternalTool": return CanvasSchema.Objects.ModuleExternalTool
      case "ModuleItem": return CanvasSchema.Objects.ModuleItem
      case "Notification": return CanvasSchema.Objects.Notification
      case "NotificationPolicy": return CanvasSchema.Objects.NotificationPolicy
      case "OutcomeAlignment": return CanvasSchema.Objects.OutcomeAlignment
      case "OutcomeCalculationMethod": return CanvasSchema.Objects.OutcomeCalculationMethod
      case "OutcomeFriendlyDescriptionType": return CanvasSchema.Objects.OutcomeFriendlyDescriptionType
      case "OutcomeProficiency": return CanvasSchema.Objects.OutcomeProficiency
      case "Page": return CanvasSchema.Objects.Page
      case "PostPolicy": return CanvasSchema.Objects.PostPolicy
      case "ProficiencyRating": return CanvasSchema.Objects.ProficiencyRating
      case "Progress": return CanvasSchema.Objects.Progress
      case "Query": return CanvasSchema.Objects.Query
      case "Quiz": return CanvasSchema.Objects.Quiz
      case "Rubric": return CanvasSchema.Objects.Rubric
      case "RubricAssessment": return CanvasSchema.Objects.RubricAssessment
      case "RubricAssociation": return CanvasSchema.Objects.RubricAssociation
      case "RubricCriterion": return CanvasSchema.Objects.RubricCriterion
      case "RubricRating": return CanvasSchema.Objects.RubricRating
      case "Section": return CanvasSchema.Objects.Section
      case "SubHeader": return CanvasSchema.Objects.SubHeader
      case "Submission": return CanvasSchema.Objects.Submission
      case "SubmissionComment": return CanvasSchema.Objects.SubmissionComment
      case "SubmissionConnection": return CanvasSchema.Objects.SubmissionConnection
      case "SubmissionDraft": return CanvasSchema.Objects.SubmissionDraft
      case "SubmissionHistory": return CanvasSchema.Objects.SubmissionHistory
      case "Term": return CanvasSchema.Objects.Term
      case "User": return CanvasSchema.Objects.User
      default: return nil
      }
    }
  }

  enum Objects {}
  enum Interfaces {}
  enum Unions {}

}