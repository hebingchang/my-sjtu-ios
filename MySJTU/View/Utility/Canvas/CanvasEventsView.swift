//
//  CanvasEventsView.swift
//  MySJTU
//
//  Created by boar on 2024/12/04.
//

import SwiftUI
import Apollo

struct CanvasEventsView: View {
    private typealias Assignment = CanvasSchema.GetAssignmentQuery.Data.Assignment
    private typealias SubmissionNode = CanvasSchema.GetAssignmentQuery.Data.Assignment.SubmissionsConnection.Node

    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @State private var assignments: [Assignment] = []
    @State private var isLoading: Bool = false
    @State private var hasLoadedOnce: Bool = false
    @State private var loadErrorMessage: String?
    @State private var showTokenExpiredAlert: Bool = false
    @State private var presentAccountPage: Bool = false

    private var canvasToken: String? {
        accounts.jaccountCanvasToken
    }

    private var shouldShowInitialLoadingState: Bool {
        assignments.isEmpty && (!hasLoadedOnce || isLoading)
    }

    var body: some View {
        ZStack {
            if shouldShowInitialLoadingState {
                CanvasLoadingView(title: "正在加载待办事项")
            } else if let loadErrorMessage, assignments.isEmpty {
                ContentUnavailableView {
                    Label("无法获取待办事项", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadErrorMessage)
                } actions: {
                    if canvasToken != nil {
                        Button("重试") {
                            Task {
                                await loadAssignments(force: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if assignments.isEmpty {
                ContentUnavailableView(
                    "暂无即将到来的待办事项",
                    systemImage: "checkmark.circle",
                    description: Text("Canvas 没有返回需要关注的近期待办事项。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let items = makeAssignmentItems(from: assignments)
                let sections = makeCourseSections(from: items)

                List {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                NavigationLink {
                                    CanvasAssignmentView(
                                        assignmentId: item.assignmentId,
                                        assignmentName: item.assignmentName
                                    )
                                } label: {
                                    CanvasEventAssignmentRow(item: item)
                                }
                            }
                        } header: {
                            CanvasCourseSectionHeader(section: section)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .contentMargins(.top, 8, for: .scrollContent)
                .refreshable {
                    await loadAssignments(force: true)
                }
            }
        }
        .navigationTitle("待办事项")
        .analyticsScreen(
            "canvas_events",
            screenClass: "CanvasEventsView",
            parameters: [
                "assignment_count": assignments.count,
                "has_token": canvasToken != nil
            ]
        )
        .animation(.easeInOut, value: isLoading)
        .task {
            await loadAssignments()
        }
        .sheet(isPresented: $presentAccountPage) {
            NavigationStack {
                AccountView(provider: .jaccount)
                    .navigationTitle("jAccount 账户")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("Canvas 错误", isPresented: $showTokenExpiredAlert) {
            Button("以后", role: .cancel) { }
            Button("前往设置") {
                presentAccountPage = true
            }
        } message: {
            Text("无法访问 Canvas，可能是令牌已被删除或重置，请重新启用 Canvas 账户")
        }
    }

    private func makeAssignmentItems(from assignments: [Assignment]) -> [CanvasEventAssignmentItem] {
        return assignments.map { assignment in
            let dueDate = assignment.dueAt.flatMap { CanvasFormatters.iso8601.date(from: $0) }
            let latestSubmission = latestSubmission(for: assignment)
            let status: CanvasEventAssignmentItem.Status

            if let latestSubmission, latestSubmission.gradingStatus == .graded {
                status = .graded(
                    score: latestSubmission.score,
                    pointsPossible: assignment.pointsPossible
                )
            } else if latestSubmission != nil {
                status = .submitted
            } else if let dueDate, dueDate < .now {
                status = .overdue
            } else if dueDate == nil {
                status = .unscheduled
            } else {
                status = .upcoming
            }

            return CanvasEventAssignmentItem(
                assignmentId: assignment.id,
                assignmentName: sanitizedName(assignment.name),
                courseName: sanitizedName(assignment.course?.name, fallback: "未命名课程"),
                dueDate: dueDate,
                pointsPossible: assignment.pointsPossible,
                status: status
            )
        }
    }

    private func makeCourseSections(from items: [CanvasEventAssignmentItem]) -> [CanvasEventCourseSection] {
        let groupedItems = Dictionary(grouping: items, by: \.courseName)

        return groupedItems.map { courseName, items in
            CanvasEventCourseSection(
                courseName: courseName,
                items: sortItems(items)
            )
        }
        .sorted { lhs, rhs in
            canvasCompareDates(
                lhs.nextDueDate,
                rhs.nextDueDate,
                order: .ascending,
                fallback: lhs.courseName.localizedStandardCompare(rhs.courseName) == .orderedAscending
            )
        }
    }

    private func sanitizedName(_ value: String?, fallback: String = "未命名待办事项") -> String {
        let sanitized = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? fallback : sanitized
    }

    private func latestSubmission(for assignment: Assignment) -> SubmissionNode? {
        guard let nodes = assignment.submissionsConnection?.nodes else {
            return nil
        }

        return nodes
            .compactMap { $0 }
            .max(by: { $0.attempt < $1.attempt })
    }

    private func sortItems(_ items: [CanvasEventAssignmentItem]) -> [CanvasEventAssignmentItem] {
        items.sorted { lhs, rhs in
            canvasCompareDates(
                lhs.dueDate,
                rhs.dueDate,
                order: .ascending,
                fallback: lhs.assignmentName.localizedStandardCompare(rhs.assignmentName) == .orderedAscending
            )
        }
    }

    @MainActor
    private func loadAssignments(force: Bool = false) async {
        guard !isLoading else {
            return
        }

        if !force && !assignments.isEmpty {
            return
        }

        hasLoadedOnce = true

        guard let token = canvasToken else {
            loadErrorMessage = "Canvas 令牌不可用，请在账户设置中重新启用。"
            AnalyticsService.logEvent(
                "canvas_events_load",
                parameters: [
                    "status": "no_token"
                ]
            )
            return
        }

        isLoading = true
        loadErrorMessage = nil

        defer {
            isLoading = false
        }

        do {
            let api = CanvasAPI(token: token)
            let events = try await api.getUpcomingEvents()
            let assignmentIDs = events.compactMap { $0.assignment?.id }

            guard !assignmentIDs.isEmpty else {
                assignments = []
                AnalyticsService.logEvent(
                    "canvas_events_load",
                    parameters: [
                        "status": "success",
                        "assignment_count": 0
                    ]
                )
                return
            }

            assignments = try await api.getAssignments(assignmentIds: assignmentIDs)
            AnalyticsService.logEvent(
                "canvas_events_load",
                parameters: [
                    "status": "success",
                    "assignment_count": assignments.count
                ]
            )
        } catch APIError.sessionExpired {
            loadErrorMessage = "Canvas 令牌可能已失效，请在账户设置中重新启用。"
            showTokenExpiredAlert = true
            AnalyticsService.logEvent(
                "canvas_events_load",
                parameters: [
                    "status": "token_expired"
                ]
            )
        } catch ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode {
            loadErrorMessage = "Canvas 令牌可能已失效，请在账户设置中重新启用。"
            showTokenExpiredAlert = true
            AnalyticsService.logEvent(
                "canvas_events_load",
                parameters: [
                    "status": "token_expired"
                ]
            )
        } catch {
            loadErrorMessage = "无法加载待办事项列表，请稍后重试。"
            AnalyticsService.logEvent(
                "canvas_events_load",
                parameters: [
                    "status": "failed",
                    "error_type": AnalyticsService.errorTypeName(error)
                ]
            )
        }
    }
}

private struct CanvasEventAssignmentItem: Identifiable {
    enum Status {
        case overdue
        case upcoming
        case submitted
        case graded(score: Double?, pointsPossible: Double?)
        case unscheduled
    }

    let assignmentId: String
    let assignmentName: String
    let courseName: String
    let dueDate: Date?
    let pointsPossible: Double?
    let status: Status

    var id: String {
        assignmentId
    }
}

private struct CanvasEventCourseSection: Identifiable {
    let courseName: String
    let items: [CanvasEventAssignmentItem]

    var id: String {
        courseName
    }

    var nextDueDate: Date? {
        items.compactMap(\.dueDate).min()
    }

    var subtitle: String {
        if let nextDueDate {
            return "\(items.count) 项 · 最早截止 \(nextDueDate.formattedCanvasRelativeDueDate())"
        }

        return "\(items.count) 项 · 暂无截止时间"
    }
}

private struct CanvasCourseSectionHeader: View {
    let section: CanvasEventCourseSection

    var body: some View {
        CanvasSectionHeader(
            title: section.courseName,
            subtitle: section.subtitle,
            systemImage: "books.vertical.fill",
            tint: .blue
        )
    }
}

private struct CanvasEventAssignmentRow: View {
    let item: CanvasEventAssignmentItem

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.assignmentName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !metadataItems.isEmpty {
                    CanvasMetadataGroup(items: metadataItems)
                }
            }

            Spacer(minLength: 12)

            CanvasStatusView(presentation: item.status.canvasStatusPresentation)
        }
        .padding(.vertical, 4)
    }

    private var metadataItems: [CanvasMetadataItem] {
        var items: [CanvasMetadataItem] = []

        items.append(
            CanvasMetadataItem(
                systemImage: dueSystemImage,
                text: dueText
            )
        )

        if let pointsPossible = item.pointsPossible, pointsPossible > 0 {
            items.append(
                CanvasMetadataItem(
                    systemImage: "chart.bar.xaxis",
                    text: "满分 \(pointsPossible.clean)"
                )
            )
        }

        return items
    }

    private var dueSystemImage: String {
        switch item.status {
        case .unscheduled:
            "calendar.badge.questionmark"
        case .overdue:
            "clock"
        default:
            "calendar"
        }
    }

    private var dueText: String {
        guard let dueDate = item.dueDate else {
            return "未设置截止时间"
        }

        switch item.status {
        case .overdue:
            return dueDate.formattedCanvasRelativeDueDate(includeOverduePrefix: true)
        default:
            return dueDate.formattedCanvasRelativeDueDate()
        }
    }
}

private extension CanvasEventAssignmentItem.Status {
    var canvasStatusPresentation: CanvasStatusPresentation {
        switch self {
        case let .graded(score, pointsPossible):
            CanvasStatusPresentation(
                title: "已评分",
                tint: .green,
                score: score,
                pointsPossible: pointsPossible
            )
        case .submitted:
            CanvasStatusPresentation(title: "已提交", tint: .teal)
        case .overdue:
            CanvasStatusPresentation(title: "已逾期", tint: .orange)
        case .upcoming:
            CanvasStatusPresentation(title: "待完成", tint: .blue)
        case .unscheduled:
            CanvasStatusPresentation(title: "待查看", tint: .secondary)
        }
    }
}

#Preview {
    NavigationStack {
        CanvasEventsView()
    }
}
