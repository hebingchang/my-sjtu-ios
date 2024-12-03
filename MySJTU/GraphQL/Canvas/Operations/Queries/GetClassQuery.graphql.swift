// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

extension CanvasSchema {
  class GetClassQuery: GraphQLQuery {
    static let operationName: String = "getClass"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query getClass($classId: ID!) { course(id: $classId) { __typename _id courseCode id assetString createdAt syllabusBody name assignmentsConnection { __typename nodes { __typename _id id htmlUrl description dueAt } } } }"#
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
          .field("_id", CanvasSchema.ID.self),
          .field("courseCode", String?.self),
          .field("id", CanvasSchema.ID.self),
          .field("assetString", String?.self),
          .field("createdAt", CanvasSchema.DateTime?.self),
          .field("syllabusBody", String?.self),
          .field("name", String.self),
          .field("assignmentsConnection", AssignmentsConnection?.self),
        ] }

        /// legacy canvas id
        var _id: CanvasSchema.ID { __data["_id"] }
        /// course short name
        var courseCode: String? { __data["courseCode"] }
        var id: CanvasSchema.ID { __data["id"] }
        var assetString: String? { __data["assetString"] }
        var createdAt: CanvasSchema.DateTime? { __data["createdAt"] }
        var syllabusBody: String? { __data["syllabusBody"] }
        var name: String { __data["name"] }
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
              .field("description", String?.self),
              .field("dueAt", CanvasSchema.DateTime?.self),
            ] }

            /// legacy canvas id
            var _id: CanvasSchema.ID { __data["_id"] }
            var id: CanvasSchema.ID { __data["id"] }
            var htmlUrl: CanvasSchema.URL? { __data["htmlUrl"] }
            var description: String? { __data["description"] }
            /// when this assignment is due
            var dueAt: CanvasSchema.DateTime? { __data["dueAt"] }
          }
        }
      }
    }
  }

}