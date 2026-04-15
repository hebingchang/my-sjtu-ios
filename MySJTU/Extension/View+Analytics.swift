//
//  View+Analytics.swift
//  MySJTU
//
//  Created by Codex on 2026/04/11.
//

import SwiftUI

private struct AnalyticsScreenModifier: ViewModifier {
    let name: String
    let screenClass: String
    let parameters: () -> [String: Any]

    func body(content: Content) -> some View {
        content.onAppear {
            AnalyticsService.logScreen(
                name,
                screenClass: screenClass,
                parameters: parameters()
            )
        }
    }
}

extension View {
    func analyticsScreen(
        _ name: String,
        screenClass: String? = nil,
        parameters: @escaping @autoclosure () -> [String: Any] = [:]
    ) -> some View {
        modifier(
            AnalyticsScreenModifier(
                name: name,
                screenClass: screenClass ?? name,
                parameters: parameters
            )
        )
    }
}
