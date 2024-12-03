//
//  Environment.swift
//  MySJTU
//
//  Created by boar on 2024/11/21.
//

import Foundation
import SwiftUI

class Alerter: ObservableObject {
    @Published var alert: Alert? {
        didSet { isShowingAlert = alert != nil }
    }
    @Published var isShowingAlert = false
}

struct Progress {
    var description: String
    var value: Float
}

class Progressor: ObservableObject {
    @Published var progress: Progress? {
        didSet {
            if progress != nil {
                isShowingProgress = true
            }
            
            if progress?.value == 1 || progress?.value == -1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    self.isShowingProgress = false
                }
            }
        }
    }
    @Published var isShowingProgress = false
}
