// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

extension CanvasSchema {
  class GetClassAssignmentsQuery: GraphQLQuery {
    static let operationName: String = "getClassAssignments"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query getClassAssignments($classId: ID!) { course(id: $classId) { __typename assignmentsConnection { __typename nodes { __typename _id id htmlUrl dueAt state name submissionsConnection { __typename nodes { __typename attempt readState score gradingStatus } } pointsPossible } } } }"#
      ))

    public var classId: ID

    public init(classId: ID) {
      self.classId = classId
    }

    public var __variables: Variables? { ["classId": classId] }

    struct Data: CanvasSchema.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("course", Course?.self, arguments: ["id": .variable("classId")]),
      ] }

      var course: Course? { __data["course"] }

      /// Course
      ///
      /// Parent Type: `Course`
      struct Course: CanvasSchema.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.Course }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("assignmentsConnection", AssignmentsConnection?.self),
        ] }

        /// returns a list of assignments.
        ///
        /// **NOTE**: for courses with grading periods, this will only return grading
        /// periods in the current course; see `AssignmentFilter` for more info.
        /// In courses with grading periods that don't have students, it is necessary
        /// to *not* filter by grading period to list assignments.
        ///
        var assignmentsConnection: AssignmentsConnection? { __data["assignmentsConnection"] }

        /// Course.AssignmentsConnection
        ///
        /// Parent Type: `AssignmentConnection`
        struct AssignmentsConnection: CanvasSchema.SelectionSet {
          let __data: DataDict
          init(_dataDict: DataDict) { __data = _dataDict }

          static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.AssignmentConnection }
          static var __selections: [ApolloAPI.Selection] { [
            .field("__typename", String.self),
            .field("nodes", [Node?]?.self),
          ] }

          /// A list of nodes.
          var nodes: [Node?]? { __data["nodes"] }

          /// Course.AssignmentsConnection.Node
          ///
          /// Parent Type: `Assignment`
          struct Node: CanvasSchema.SelectionSet {
            let __data: DataDict
            init(_dataDict: DataDict) { __data = _dataDict }

            static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.Assignment }
            static var __selections: [ApolloAPI.Selection] { [
              .field("__typename", String.self),
              .field("_id", CanvasSchema.ID.self),
              .field("id", CanvasSchema.ID.self),
              .field("htmlUrl", CanvasSchema.URL?.self),
              .field("dueAt", CanvasSchema.DateTime?.self),
              .field("state", GraphQLEnum<CanvasSchema.AssignmentState>.self),
              .field("name", String?.self),
              .field("submissionsConnection", SubmissionsConnection?.self),
              .field("pointsPossible", Double?.self),
            ] }

            /// legacy canvas id
            var _id: CanvasSchema.ID { __data["_id"] }
            var id: CanvasSchema.ID { __data["id"] }
            var htmlUrl: CanvasSchema.URL? { __data["htmlUrl"] }
            /// when this assignment is due
            var dueAt: CanvasSchema.DateTime? { __data["dueAt"] }
            var state: GraphQLEnum<CanvasSchema.AssignmentState> { __data["state"] }
            var name: String? { __data["name"] }
            /// submissions for this assignment
            var submissionsConnection: SubmissionsConnection? { __data["submissionsConnection"] }
            /// the assignment is out of this many points
            var pointsPossible: Double? { __data["pointsPossible"] }

            /// Course.AssignmentsConnection.Node.SubmissionsConnection
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

              /// Course.AssignmentsConnection.Node.SubmissionsConnection.Node
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
          }
        }
      }
    }
  }

}