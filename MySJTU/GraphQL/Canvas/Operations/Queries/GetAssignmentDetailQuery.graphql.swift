// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

extension CanvasSchema {
  class GetAssignmentDetailQuery: GraphQLQuery {
    static let operationName: String = "getAssignmentDetail"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query getAssignmentDetail($assignmentId: ID!) { assignment(id: $assignmentId) { __typename course { __typename id name } description dueAt htmlUrl id pointsPossible name submissionTypes allowedExtensions submissionsConnection { __typename nodes { __typename id attempt readState score gradingStatus createdAt } } } }"#
      ))

    public var assignmentId: ID

    public init(assignmentId: ID) {
      self.assignmentId = assignmentId
    }

    public var __variables: Variables? { ["assignmentId": assignmentId] }

    struct Data: CanvasSchema.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("assignment", Assignment?.self, arguments: ["id": .variable("assignmentId")]),
      ] }
      static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
        GetAssignmentDetailQuery.Data.self
      ] }

      var assignment: Assignment? { __data["assignment"] }

      /// Assignment
      ///
      /// Parent Type: `Assignment`
      struct Assignment: CanvasSchema.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.Assignment }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("course", Course?.self),
          .field("description", String?.self),
          .field("dueAt", CanvasSchema.DateTime?.self),
          .field("htmlUrl", CanvasSchema.URL?.self),
          .field("id", CanvasSchema.ID.self),
          .field("pointsPossible", Double?.self),
          .field("name", String?.self),
          .field("submissionTypes", [GraphQLEnum<CanvasSchema.SubmissionType>]?.self),
          .field("allowedExtensions", [String]?.self),
          .field("submissionsConnection", SubmissionsConnection?.self),
        ] }
        static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
          GetAssignmentDetailQuery.Data.Assignment.self
        ] }

        var course: Course? { __data["course"] }
        var description: String? { __data["description"] }
        /// when this assignment is due
        var dueAt: CanvasSchema.DateTime? { __data["dueAt"] }
        var htmlUrl: CanvasSchema.URL? { __data["htmlUrl"] }
        var id: CanvasSchema.ID { __data["id"] }
        /// the assignment is out of this many points
        var pointsPossible: Double? { __data["pointsPossible"] }
        var name: String? { __data["name"] }
        var submissionTypes: [GraphQLEnum<CanvasSchema.SubmissionType>]? { __data["submissionTypes"] }
        /// permitted uploaded file extensions (e.g. ['doc', 'xls', 'txt'])
        var allowedExtensions: [String]? { __data["allowedExtensions"] }
        /// submissions for this assignment
        var submissionsConnection: SubmissionsConnection? { __data["submissionsConnection"] }

        /// Assignment.Course
        ///
        /// Parent Type: `Course`
        struct Course: CanvasSchema.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.Course }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("id", CanvasSchema.ID.self),
            .field("name", String.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            GetAssignmentDetailQuery.Data.Assignment.Course.self
          ] }

          var id: CanvasSchema.ID { __data["id"] }
          var name: String { __data["name"] }
        }

        /// Assignment.SubmissionsConnection
        ///
        /// Parent Type: `SubmissionConnection`
        struct SubmissionsConnection: CanvasSchema.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.SubmissionConnection }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("nodes", [Node?]?.self),
          ] }
          static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
            GetAssignmentDetailQuery.Data.Assignment.SubmissionsConnection.self
          ] }

          /// A list of nodes.
          var nodes: [Node?]? { __data["nodes"] }

          /// Assignment.SubmissionsConnection.Node
          ///
          /// Parent Type: `Submission`
          struct Node: CanvasSchema.SelectionSet {
            let __data: DataDict
            init(_dataDict: DataDict) { __data = _dataDict }

            static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.Submission }
            static var __selections: [ApolloAPI.Selection] { [
              .field("__typename", String.self),
              .field("id", CanvasSchema.ID.self),
              .field("attempt", Int.self),
              .field("readState", String?.self),
              .field("score", Double?.self),
              .field("gradingStatus", GraphQLEnum<CanvasSchema.SubmissionGradingStatus>?.self),
              .field("createdAt", CanvasSchema.DateTime?.self),
            ] }
            static var __fulfilledFragments: [any ApolloAPI.SelectionSet.Type] { [
              GetAssignmentDetailQuery.Data.Assignment.SubmissionsConnection.Node.self
            ] }

            var id: CanvasSchema.ID { __data["id"] }
            var attempt: Int { __data["attempt"] }
            var readState: String? { __data["readState"] }
            var score: Double? { __data["score"] }
            var gradingStatus: GraphQLEnum<CanvasSchema.SubmissionGradingStatus>? { __data["gradingStatus"] }
            var createdAt: CanvasSchema.DateTime? { __data["createdAt"] }
          }
        }
      }
    }
  }

}