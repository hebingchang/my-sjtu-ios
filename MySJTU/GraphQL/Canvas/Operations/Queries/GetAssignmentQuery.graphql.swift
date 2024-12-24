// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

extension CanvasSchema {
  class GetAssignmentQuery: GraphQLQuery {
    static let operationName: String = "getAssignment"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query getAssignment($assignmentId: ID!) { assignment(id: $assignmentId) { __typename submissionsConnection { __typename nodes { __typename attempt readState score gradingStatus } } course { __typename id name } id pointsPossible name state dueAt htmlUrl } }"#
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
          .field("submissionsConnection", SubmissionsConnection?.self),
          .field("course", Course?.self),
          .field("id", CanvasSchema.ID.self),
          .field("pointsPossible", Double?.self),
          .field("name", String?.self),
          .field("state", GraphQLEnum<CanvasSchema.AssignmentState>.self),
          .field("dueAt", CanvasSchema.DateTime?.self),
          .field("htmlUrl", CanvasSchema.URL?.self),
        ] }

        /// submissions for this assignment
        var submissionsConnection: SubmissionsConnection? { __data["submissionsConnection"] }
        var course: Course? { __data["course"] }
        var id: CanvasSchema.ID { __data["id"] }
        /// the assignment is out of this many points
        var pointsPossible: Double? { __data["pointsPossible"] }
        var name: String? { __data["name"] }
        var state: GraphQLEnum<CanvasSchema.AssignmentState> { __data["state"] }
        /// when this assignment is due
        var dueAt: CanvasSchema.DateTime? { __data["dueAt"] }
        var htmlUrl: CanvasSchema.URL? { __data["htmlUrl"] }

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
              .field("attempt", Int.self),
              .field("readState", String?.self),
              .field("score", Double?.self),
              .field("gradingStatus", GraphQLEnum<CanvasSchema.SubmissionGradingStatus>?.self),
            ] }

            var attempt: Int { __data["attempt"] }
            var readState: String? { __data["readState"] }
            var score: Double? { __data["score"] }
            var gradingStatus: GraphQLEnum<CanvasSchema.SubmissionGradingStatus>? { __data["gradingStatus"] }
          }
        }

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

          var id: CanvasSchema.ID { __data["id"] }
          var name: String { __data["name"] }
        }
      }
    }
  }

}