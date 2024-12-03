// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

extension CanvasSchema.Objects {
  /// A PostPolicy sets the policy for whether a Submission's grades are posted
  /// automatically or manually. A PostPolicy can be set at the Course and/or
  /// Assignment level.
  ///
  static let PostPolicy = ApolloAPI.Object(
    typename: "PostPolicy",
    implementedInterfaces: [
      CanvasSchema.Interfaces.Node.self,
      CanvasSchema.Interfaces.LegacyIDInterface.self
    ]
  )
}