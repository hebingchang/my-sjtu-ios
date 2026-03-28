//
//  CanvasAssignmentView.swift
//  MySJTU
//
//  Created by boar on 2024/12/05.
//

import SwiftUI
import Apollo

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
    private typealias Assignment = CanvasSchema.GetAssignmentDetailQuery.Data.Assignment

    let assignmentId: String
    let assignmentName: String

    @AppStorage("accounts") private var accounts: [WebAuthAccount] = []
    @State private var assignment: Assignment?
    @State private var isLoading: Bool = true
    @State private var loadErrorMessage: String?

    private var canvasToken: String? {
        accounts.jaccountCanvasToken
    }

    var body: some View {
        Group {
            if isLoading {
                CanvasLoadingView(title: "正在加载作业详情")
            } else if let loadErrorMessage {
                ContentUnavailableView {
                    Label("无法获取作业详情", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadErrorMessage)
                } actions: {
                    if canvasToken != nil {
                        Button("重试") {
                            Task {
                                await loadAssignment(force: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let assignment {
                CanvasAssignmentDetailContent(assignment: assignment)
            } else {
                ContentUnavailableView(
                    "暂无作业详情",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Canvas 没有返回更多作业信息。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(assignmentName)
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut, value: isLoading)
        .task(id: assignmentId) {
            await loadAssignment()
        }
    }

    @MainActor
    private func loadAssignment(force: Bool = false) async {
        if !force && assignment != nil {
            return
        }

        guard let token = canvasToken else {
            loadErrorMessage = "Canvas 令牌不可用，请在账户设置中重新启用。"
            isLoading = false
            return
        }

        isLoading = true
        loadErrorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let api = CanvasAPI(token: token)
            assignment = try await api.getAssignmentDetail(assignmentId: assignmentId)
        } catch ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode {
            loadErrorMessage = "Canvas 令牌可能已失效，请在账户设置中重新启用。"
        } catch {
            loadErrorMessage = "无法加载作业详情，请稍后重试。"
        }
    }
}

private struct CanvasAssignmentDetailContent: View {
    typealias Assignment = CanvasSchema.GetAssignmentDetailQuery.Data.Assignment
    typealias Submission = CanvasSchema.GetAssignmentDetailQuery.Data.Assignment.SubmissionsConnection.Node

    let assignment: Assignment

    private var submissionItems: [Submission] {
        assignment.submissionsConnection?.nodes?.compactMap { $0 } ?? []
    }

    var body: some View {
        List {
            CanvasInfoRow(
                title: "截止日期",
                value: formattedDate(assignment.dueAt) ?? "长期"
            )

            if let pointsPossible = assignment.pointsPossible {
                CanvasInfoRow(
                    title: "满分",
                    value: pointsPossible.clean
                )
            }

            if let submissionTypes = assignment.submissionTypes, !submissionTypes.isEmpty {
                CanvasInfoRow(
                    title: "提交",
                    value: submissionTypes
                        .map { submissionTypeDescription[$0.value] ?? "未知 (\($0.rawValue))" }
                        .joined(separator: "或"),
                    multiline: true
                )
            }

            ForEach(submissionItems, id: \.self) { submission in
                Section(header: Text("提交 #\(submission.attempt)")) {
                    if let createdAt = submission.createdAt {
                        CanvasInfoRow(
                            title: "提交时间",
                            value: formattedDate(createdAt) ?? createdAt
                        )
                    }

                    if let gradingStatus = submission.gradingStatus {
                        CanvasInfoRow(
                            title: "评分状态",
                            value: gradingStatusDescription[gradingStatus.value] ?? "未知 \(gradingStatus.rawValue)"
                        )
                    }

                    if let score = submission.score {
                        CanvasInfoRow(
                            title: "评分",
                            value: score.clean
                        )
                    }
                }
            }

            if let description = assignment.description,
               !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section(header: Text("作业详情")) {
                    HTMLTextView(htmlContent: description)
                }
            }
        }
    }

    private func formattedDate(_ value: String?) -> String? {
        guard let value,
              let date = CanvasFormatters.iso8601.date(from: value)
        else {
            return nil
        }

        return date.formatted()
    }
}
