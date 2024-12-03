//
//  CircularProgressView.swift
//  MySJTU
//
//  Created by boar on 2024/11/22.
//

import SwiftUI

struct CircularProgressView: View {
    let progress: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            let lineWidth = min(geometry.size.width, geometry.size.height) / 10
            
            ZStack {
                // Background for the progress bar
                Circle()
                    .stroke(lineWidth: lineWidth)
                    .opacity(0.1)
                    .foregroundColor(Color(UIColor.tintColor))
                
                // Foreground or the actual progress bar
                Circle()
                    .trim(from: 0.0, to: min(progress, 1.0))
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .foregroundColor(Color(UIColor.tintColor))
                    .rotationEffect(Angle(degrees: 270.0))
                    .animation(.easeInOut, value: progress)
            }
        }
    }
}
