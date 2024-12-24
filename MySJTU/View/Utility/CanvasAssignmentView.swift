//
//  CanvasAssignmentView.swift
//  MySJTU
//
//  Created by boar on 2024/12/05.
//

import SwiftUI

private let submissionTypeDescription: [CanvasSchema.SubmissionType?: String] = [
    .attendance: "出勤",
    .basicLtiLaunch: "基本 LTI",
    .discussionTopic: "讨论",
    .externalTool: "外部工具",
    .mediaRecording: "媒体录音",
    CanvasSchema.SubmissionType.none: "无",
    .notGraded: "未评分",
    .onPaper: "书面",
    .onlineQuiz: "在线测验",
    .onlineTextEntry: "文本输入框",
    .onlineUpload: "上传文件",
    .onlineUrl: "在线 URL",
    .studentAnnotation: "学生注释",
    .wikiPage: "wiki page",
]

private let gradingStatusDescription: [CanvasSchema.SubmissionGradingStatus?: String] = [
    .excused: "已免除",
    .graded: "已评分",
    .needsGrading: "等待评分",
    .needsReview: "等待审核",
]
    

struct CanvasAssignmentView: View {
    var assignmentId: String
    var assignmentName: String
    private let dateFormatter = ISO8601DateFormatter()

    @State private var loading: Bool = true
    @State private var assignment: CanvasSchema.GetAssignmentDetailQuery.Data.Assignment?
    @State private var descriptionText: AttributedString?
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []

    var body: some View {
        let account = accounts.first {
            $0.provider == .jaccount
        }

        ZStack {
            if loading {
                VStack {
                    ProgressView()
                }
                .task {
                    do {
                        if let account, account.enabledFeatures.contains(.canvas), let token = account.bizData["canvas_token"] {
                            let api = CanvasAPI(token: token)
                            self.assignment = try await api.getAssignmentDetail(assignmentId: assignmentId)
                            
                            DispatchQueue.main.async {
                                if let description = self.assignment?.description {
                                    if let data = description.data(using: .utf8) {
                                        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                                            .documentType: NSAttributedString.DocumentType.html,
                                            .characterEncoding: String.Encoding.utf8.rawValue
                                        ]
                                        if let syllabusBody = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                                            self.descriptionText = try? AttributedString(syllabusBody, including: \.uiKit)
                                            self.descriptionText?.foregroundColor = UIColor.label
                                            self.descriptionText?.font = UIFont.preferredFont(forTextStyle: .callout)
                                        }
                                    }
                                }
                                loading = false
                            }
                        }
                    } catch {
                        print(error)
                        loading = false
                    }
                }
            } else if let assignment {
                let dateFormatter = ISO8601DateFormatter()
                
                List {
                    HStack {
                        Text("截止日期")
                        Spacer()
                        Text(assignment.dueAt != nil ? dateFormatter.date(from: assignment.dueAt!)!.formatted() : "长期")
                            .font(.callout)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                    
                    if let pointsPossible = assignment.pointsPossible {
                        HStack {
                            Text("满分")
                            Spacer()
                            Text("\(pointsPossible.clean)")
                                .font(.callout)
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                        }
                    }
                    
                    if let submissionTypes = assignment.submissionTypes {
                        HStack {
                            Text("提交")
                            Spacer()
                            Text(submissionTypes.map { submissionTypeDescription[$0.value] ?? "未知 (\($0.rawValue))" }.joined(separator: "或"))
                                .font(.callout)
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                        }
                    }
                    
                    if let submissions = assignment.submissionsConnection?.nodes, submissions.count > 0 {
                        ForEach(submissions, id: \.self) { submission in
                            if let submission {
                                Section(header: Text("提交 #\(submission.attempt)")) {
                                    if let createdAt = submission.createdAt {
                                        HStack {
                                            Text("提交时间")
                                            Spacer()
                                            Text("\(dateFormatter.date(from: createdAt)!.formatted())")
                                                .font(.callout)
                                                .foregroundStyle(Color(UIColor.secondaryLabel))
                                            
                                        }
                                    }

                                    if let gradingStatus = submission.gradingStatus {
                                        HStack {
                                            Text("评分状态")
                                            Spacer()
                                            Text("\(gradingStatusDescription[gradingStatus.value] ?? "未知 \(gradingStatus.rawValue)")")
                                                .font(.callout)
                                                .foregroundStyle(Color(UIColor.secondaryLabel))
                                            
                                        }
                                    }
                                    
                                    if let score = submission.score {
                                        HStack {
                                            Text("评分")
                                            Spacer()
                                            Text("\(score.clean)")
                                                .font(.callout)
                                                .foregroundStyle(Color(UIColor.secondaryLabel))
                                            
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if let descriptionText {
                        Section(header: Text("作业详情")) {
                            Text(descriptionText)
                        }
                    }
                }
            }
        }
        .navigationTitle(assignmentName)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut, value: loading)
    }
}
