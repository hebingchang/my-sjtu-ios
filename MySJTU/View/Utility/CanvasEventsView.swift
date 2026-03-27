//
//  CanvasEventsView.swift
//  MySJTU
//
//  Created by boar on 2024/12/04.
//

import SwiftUI

struct CanvasEventsView: View {
    @State private var loading: Bool = true
    @State private var assignments: [CanvasSchema.GetAssignmentQuery.Data.Assignment] = []
    @State private var courseGroup: [String?: [CanvasSchema.GetAssignmentQuery.Data.Assignment]] = [:]
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []

    var body: some View {
        let account = accounts.first {
            $0.provider == .jaccount
        }
        
        ZStack {
            let dateFormatter = ISO8601DateFormatter()

            if loading {
                VStack {
                    ProgressView()
                }
                .task {
                    do {
                        if let account, account.enabledFeatures.contains(.canvas), let token = account.bizData["canvas_token"] {
                            let api = CanvasAPI(token: token)
                            let events = try await api.getUpcomingEvents()
                            
                            self.assignments = try await api.getAssignments(assignmentIds: events.map { $0.assignment!.id }).sorted {
                                if $0.dueAt == nil && $1.dueAt == nil {
                                    return $0.id > $1.id
                                } else if $0.dueAt == nil && $1.dueAt != nil {
                                    return false
                                } else if $0.dueAt != nil && $1.dueAt == nil {
                                    return true
                                } else {
                                    return $0.dueAt == $1.dueAt ? ($0.id > $1.id) : dateFormatter.date(from: $0.dueAt!)! > dateFormatter.date(from: $1.dueAt!)!
                                }
                            }
                            self.courseGroup = Dictionary(grouping: assignments, by: { $0.course?.name })
                        }
                    } catch {
                        print(error)
                    }
                    loading = false
                }
            } else {
                List {
                    ForEach(courseGroup.sorted { $0.value[0].dueAt! > $1.value[0].dueAt! }, id: \.key) { key, value in
                        Section(header: Text(key ?? "")) {
                            ForEach(value, id: \.id) { assignment in
                                NavigationLink {
                                    CanvasAssignmentView(assignmentId: assignment.id, assignmentName: assignment.name ?? "")
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text((assignment.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                                                .fontWeight(.medium)
                                            
                                            if let dueAt = assignment.dueAt {
                                                Text("截止时间 \(dateFormatter.date(from: dueAt)!.formatted())")
                                                    .font(.caption)
                                                    .foregroundColor(Color(UIColor.secondaryLabel))
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        if let submissions = assignment.submissionsConnection?.nodes, submissions.count > 0 {
                                            let lastSubmission = submissions.sorted {
                                                $0!.attempt < $1!.attempt
                                            }.last!
                                            
                                            if lastSubmission?.gradingStatus == .graded, let score = lastSubmission?.score {
                                                HStack(alignment: .bottom, spacing: 0) {
                                                    Text("\(score.clean)")
                                                    if let pointsPossible = assignment.pointsPossible, pointsPossible > 0 {
                                                        Text(" / \(pointsPossible.clean)")
                                                            .font(.caption)
                                                    }
                                                }
                                            } else {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("作业")
        .animation(.easeInOut, value: loading)
    }
}

#Preview {
    CanvasEventsView()
}
