//
//  ProgressOverlay.swift
//  MySJTU
//
//  Created by boar on 2024/11/22.
//

import SwiftUI
import Lottie
import WidgetKit

struct ProgressOverlay: View {
    var isShowingProgress: Bool
    var progress: Progress?
    
    var body: some View {
        if let progress {
            VStack {
                if isShowingProgress {
                    VStack(spacing: 14) {
                        ZStack {
                            if progress.value == 1 || progress.value == -1 {
                                if progress.value == 1 {
                                    LottieView {
                                        try await DotLottieFile.named("Success")
                                    }
                                    .playing(loopMode: .playOnce)
                                    .frame(width: 96, height: 96)
                                } else {
                                    LottieView {
                                        try await DotLottieFile.named("Warning")
                                    }
                                    .playing(loopMode: .playOnce)
                                    .frame(width: 84, height: 84)
                                }
                            } else {
                                CircularProgressView(progress: CGFloat(progress.value))
                                    .frame(width: 56, height: 56)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .animation(.easeInOut, value: progress.value)
                        
                        Text(progress.description)
                            .font(.headline)
                            .animation(.easeInOut, value: progress.description)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
                }
            }
            .sensoryFeedback(.success, trigger: progress.value) { old, new in
                new == 1
            }
            .sensoryFeedback(.error, trigger: progress.value) { old, new in
                new == -1
            }
        }
    }
}
