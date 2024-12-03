//
//  ScrollView.swift
//  MySJTU
//
//  Created by boar on 2024/10/21.
//

import SwiftUI

extension View {
  func disableBounces() -> some View {
    modifier(DisableBouncesModifier())
  }
}

struct DisableBouncesModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
    .onAppear {
      UIScrollView.appearance().bounces = false
    }
    .onDisappear {
      UIScrollView.appearance().bounces = true
    }
  }
}
