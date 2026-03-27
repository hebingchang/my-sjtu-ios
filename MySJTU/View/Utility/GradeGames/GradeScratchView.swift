//
//  GradeScratchView.swift
//  MySJTU
//
//  Created by boar on 2025/01/18.
//

import SwiftUI

struct GradeScratchView: View {
    let grade: ElectSysAPI.Grade
    let semester: Semester
    
    @Environment(\.dismiss) private var dismiss
    @AppStorage("exam.shownGrades") var shownGrades: [String] = []

    @State private var completedStrokes = [[CGPoint]]()
    @State private var currentStroke = [CGPoint]()
    @State private var selection: Int = 0
    @State private var topShine = true
    @State private var enableTopShine = false
    @State private var clearScratchArea = false
    private let gridSize = 5
    private let gridCellSize = 50

    private let scratchClearAmount: CGFloat = 0.8

    var body: some View {
        VStack {
            Spacer()
            Text(grade.courseName)
                .font(.title)
                .fontWeight(.bold)
            Text("\(String(semester.year))\(["秋", "春", "夏"][semester.semester - 1])・\(grade.teacher)")
                .foregroundStyle(.secondary)
            
            ZStack {
                // MARK: Scratchable TOP view
                RoundedRectangle(cornerRadius: 20)
                    .fill(.gray)
                    .frame(width: 250, height: 100)
                    .overlay {
                        VStack(spacing: 10) {
                            ForEach(1...3, id: \.self) { _ in
                                HStack {
                                    ForEach(1...5, id: \.self) { _ in
                                        Text("刮一刮")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .rotationEffect(.degrees(330))
                                    }
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .compositingGroup()
                    .opacity(clearScratchArea ? 0 : 1)
                
                // MARK: Full REVEAL view
                RoundedRectangle(cornerRadius: 20)
                    .fill(.background)
                    .strokeBorder(Color(UIColor.tertiaryLabel), style: .init(lineWidth: 1, dash: [6]))
                    .frame(width: 250, height: 100)
                    .overlay {
                        Text("\(grade.score)")
                            .font(.system(size: 56, design: .rounded))
                    }
                    .compositingGroup()
                    .opacity(clearScratchArea ? 1 : 0)

                // MARK: Partial REVEAL view
                RoundedRectangle(cornerRadius: 20)
                    .fill(.background)
                    .strokeBorder(Color(UIColor.tertiaryLabel), style: .init(lineWidth: 1, dash: [6]))
                    .frame(width: 250, height: 100)
                    .overlay {
                        Text("\(grade.score)")
                            .font(.system(size: 56, design: .rounded))
                    }
                    .mask(
                        scratchPath(from: completedStrokes + [currentStroke])
                            .stroke(style: StrokeStyle(lineWidth: 36, lineCap: .round, lineJoin: .round))
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged({ value in
                                currentStroke.append(value.location)
//                                let feedbackGen = UIImpactFeedbackGenerator(style: .soft)
//                                feedbackGen.impactOccurred()
                            })
                            .onEnded { _ in
                                if !currentStroke.isEmpty {
                                    completedStrokes.append(currentStroke)
                                    currentStroke.removeAll(keepingCapacity: true)
                                }

                                // Create a CGPath from the drawn points
                                let cgpath = scratchPath(from: completedStrokes).cgPath
                                
                                // Thicken the path to match the stroke width
                                let thickenedPath = cgpath.copy(strokingWithWidth: 36, lineCap: .round, lineJoin: .round, miterLimit: 10)
                                
                                var scratchedCount = 0
                                
                                // Check if each grid cell's center point is within the thickened path
                                for i in [75, 100, 125, 150, 175] {
                                    for j in [25, 50, 75] {
                                        let point = CGPoint(x: i, y: j)
                                        if thickenedPath.contains(point) {
                                            scratchedCount += 1
                                        }
                                    }
                                }
                                
                                // print(scratchedCount)
                                
                                // If scratched area exceeds the threshold, clear the top view
                                if scratchedCount >= 10 {
                                    withAnimation {
                                        clearScratchArea = true
                                    }
                                    
                                    if !shownGrades.contains(grade.id) {
                                        shownGrades.append(grade.id)
                                    }
                                }
                            }
                    )
                    .opacity(clearScratchArea ? 0 : 1)
            }
            .padding([.vertical], 40)
            
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("返回")
                    .frame(width: 250)
                    .padding([.top, .bottom], 6)
            }
            .buttonStyle(.borderedProminent)
            .opacity(clearScratchArea ? 1 : 0)
            .disabled(clearScratchArea ? false : true)
            Spacer()
        }
        .padding()
    }

    private func scratchPath(from strokes: [[CGPoint]]) -> Path {
        Path { path in
            for stroke in strokes where !stroke.isEmpty {
                path.move(to: stroke[0])
                if stroke.count == 1 {
                    path.addLine(to: stroke[0])
                } else {
                    path.addLines(Array(stroke.dropFirst()))
                }
            }
        }
    }
}
