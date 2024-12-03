//
//  View.swift
//  MySJTU
//
//  Created by boar on 2024/11/26.
//

import SwiftUI

extension View {
    @ViewBuilder func `if`<T>(_ condition: Bool, transform: (Self) -> T) -> some View where T : View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
