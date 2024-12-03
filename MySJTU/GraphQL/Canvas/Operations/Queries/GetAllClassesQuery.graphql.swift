// @generated
// This file was automatically generated and should not be edited.

@_exported import ApolloAPI

extension CanvasSchema {
  class GetAllClassesQuery: GraphQLQuery {
    static let operationName: String = "getAllClasses"
    static let operationDocument: ApolloAPI.OperationDocument = .init(
      definition: .init(
        #"query getAllClasses { allCourses { __typename _id id name courseCode } }"#
      ))

    public init() {}

    struct Data: CanvasSchema.SelectionSet {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("allCourses", [AllCourse]?.self),
      ] }

      /// All courses viewable by the current user
      var allCourses: [AllCourse]? { __data["allCourses"] }

      /// AllCourse
      ///
      /// Parent Type: `Course`
      struct AllCourse: CanvasSchema.SelectionSet {
        let __data: DataDict
        init(_dataDict: DataDict) { __data = _dataDict }

        static var __parentType: any ApolloAPI.ParentType { CanvasSchema.Objects.Course }
        static var __selections: [ApolloAPI.Selection] { [
          .field("__typename", String.self),
          .field("_id", CanvasSchema.ID.self),
          .field("id", CanvasSchema.ID.self),
          .field("name", String.self),
          .field("courseCode", String?.self),
        ] }

        /// legacy canvas id
        var _id: CanvasSchema.ID { __data["_id"] }
        var id: CanvasSchema.ID { __data["id"] }
        var name: String { __data["name"] }
        /// course short name
        var courseCode: String? { __data["courseCode"] }
      }
    }
  }

}