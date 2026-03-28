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

    private static let objectTypeMap: [String: ApolloAPI.Object] = [
      "Account": CanvasSchema.Objects.Account,
      "AssessmentRequest": CanvasSchema.Objects.AssessmentRequest,
      "Assignment": CanvasSchema.Objects.Assignment,
      "AssignmentConnection": CanvasSchema.Objects.AssignmentConnection,
      "AssignmentGroup": CanvasSchema.Objects.AssignmentGroup,
      "AssignmentOverride": CanvasSchema.Objects.AssignmentOverride,
      "CommentBankItem": CanvasSchema.Objects.CommentBankItem,
      "CommunicationChannel": CanvasSchema.Objects.CommunicationChannel,
      "ContentTag": CanvasSchema.Objects.ContentTag,
      "Conversation": CanvasSchema.Objects.Conversation,
      "Course": CanvasSchema.Objects.Course,
      "Discussion": CanvasSchema.Objects.Discussion,
      "DiscussionEntry": CanvasSchema.Objects.DiscussionEntry,
      "DiscussionEntryDraft": CanvasSchema.Objects.DiscussionEntryDraft,
      "Enrollment": CanvasSchema.Objects.Enrollment,
      "ExternalTool": CanvasSchema.Objects.ExternalTool,
      "ExternalUrl": CanvasSchema.Objects.ExternalUrl,
      "File": CanvasSchema.Objects.File,
      "GradingPeriod": CanvasSchema.Objects.GradingPeriod,
      "Group": CanvasSchema.Objects.Group,
      "GroupMembership": CanvasSchema.Objects.GroupMembership,
      "GroupSet": CanvasSchema.Objects.GroupSet,
      "InternalSetting": CanvasSchema.Objects.InternalSetting,
      "LearningOutcome": CanvasSchema.Objects.LearningOutcome,
      "LearningOutcomeGroup": CanvasSchema.Objects.LearningOutcomeGroup,
      "MediaObject": CanvasSchema.Objects.MediaObject,
      "MediaTrack": CanvasSchema.Objects.MediaTrack,
      "MessageableContext": CanvasSchema.Objects.MessageableContext,
      "MessageableUser": CanvasSchema.Objects.MessageableUser,
      "Module": CanvasSchema.Objects.Module,
      "ModuleExternalTool": CanvasSchema.Objects.ModuleExternalTool,
      "ModuleItem": CanvasSchema.Objects.ModuleItem,
      "Notification": CanvasSchema.Objects.Notification,
      "NotificationPolicy": CanvasSchema.Objects.NotificationPolicy,
      "OutcomeAlignment": CanvasSchema.Objects.OutcomeAlignment,
      "OutcomeCalculationMethod": CanvasSchema.Objects.OutcomeCalculationMethod,
      "OutcomeFriendlyDescriptionType": CanvasSchema.Objects.OutcomeFriendlyDescriptionType,
      "OutcomeProficiency": CanvasSchema.Objects.OutcomeProficiency,
      "Page": CanvasSchema.Objects.Page,
      "PostPolicy": CanvasSchema.Objects.PostPolicy,
      "ProficiencyRating": CanvasSchema.Objects.ProficiencyRating,
      "Progress": CanvasSchema.Objects.Progress,
      "Query": CanvasSchema.Objects.Query,
      "Quiz": CanvasSchema.Objects.Quiz,
      "Rubric": CanvasSchema.Objects.Rubric,
      "RubricAssessment": CanvasSchema.Objects.RubricAssessment,
      "RubricAssociation": CanvasSchema.Objects.RubricAssociation,
      "RubricCriterion": CanvasSchema.Objects.RubricCriterion,
      "RubricRating": CanvasSchema.Objects.RubricRating,
      "Section": CanvasSchema.Objects.Section,
      "SubHeader": CanvasSchema.Objects.SubHeader,
      "Submission": CanvasSchema.Objects.Submission,
      "SubmissionComment": CanvasSchema.Objects.SubmissionComment,
      "SubmissionConnection": CanvasSchema.Objects.SubmissionConnection,
      "SubmissionDraft": CanvasSchema.Objects.SubmissionDraft,
      "SubmissionHistory": CanvasSchema.Objects.SubmissionHistory,
      "Term": CanvasSchema.Objects.Term,
      "User": CanvasSchema.Objects.User
    ]

    static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
      objectTypeMap[typename]
    }
  }

  enum Objects {}
  enum Interfaces {}
  enum Unions {}

}