//
//  ClassView.swift
//  MySJTU
//
//  Created by boar on 2024/11/22.
//

import SwiftUI
import GRDB
import Apollo

struct ClassView: View {
    private typealias AssignmentNode = CanvasSchema.GetClassAssignmentsQuery.Data.Course.AssignmentsConnection.Node
    private typealias AssignmentSubmissionNode = CanvasSchema.GetClassAssignmentsQuery.Data.Course.AssignmentsConnection.Node.SubmissionsConnection.Node

    var scheduleInfo: ScheduleInfo

    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @State private var classRemark: ClassRemark?
    @State private var canvasClass: CanvasClass?
    @State private var canvasClassInfo: CanvasSchema.GetClassQuery.Data.Course?
    @State private var canvasCourses: [CanvasCourseOption] = []
    @State private var assignments: [AssignmentNode]?
    @State private var assignmentLoadErrorMessage: String?
    @State private var showError: Bool = false
    @State private var presentAccountPage: Bool = false
    @State private var canvasCourseLoadErrorMessage: String?
    @State private var canvasSaveErrorMessage: String?
    @State private var showCanvasSaveError: Bool = false
    @State private var isLoadingCanvasCourses: Bool = false
    @State private var isLoadingAssignments: Bool = false
    @State private var isSavingCanvasMatch: Bool = false
    @State private var errorDetail: ClassViewError?

    private enum ClassViewError: Error {
        case canvasTokenExpired
    }

    private var canvasToken: String? {
        accounts.jaccountCanvasToken
    }

    private var teacherNames: String {
        if let teachers = scheduleInfo.schedule.teachers, teachers.count > 0 {
            return teachers.joined(separator: "、")
        }
        return scheduleInfo.class_.teachers.joined(separator: "、")
    }

    private var isCanvasFeatureAvailable: Bool {
        accounts.jaccountAccount?.enabledFeatures.contains(.canvas) == true || canvasClass != nil
    }

    private var selectedCanvasCourseDescription: String {
        guard let canvasClassID = canvasClass?.id else {
            return "尚未匹配到 Canvas 课程"
        }

        if let canvasCourse = canvasCourses.idDictionary[canvasClassID] {
            return canvasCourse.name
        }

        if let canvasClassInfo {
            return canvasClassInfo.name
        }

        return "已匹配到一个当前不可用的 Canvas 课程"
    }

    private var canvasPickerSubtitle: String {
        if isSavingCanvasMatch {
            return "正在保存课程匹配"
        }

        if let canvasCourseLoadErrorMessage {
            return canvasCourseLoadErrorMessage
        }

        if isLoadingCanvasCourses && canvasCourses.isEmpty {
            return "正在加载 Canvas 课程列表"
        }

        if canvasToken == nil {
            return "Canvas 令牌不可用，请重新启用账户"
        }

        return selectedCanvasCourseDescription
    }

    var body: some View {
        classInfoPage
        .animation(.easeInOut, value: assignments)
        .task {
            await loadClassRemark()
        }
        .task {
            await loadCanvasClassIfNeeded()
        }
        .task {
            await loadCanvasCoursesIfNeeded()
        }
        .onChange(of: canvasClass?.id) {
            canvasClassInfo = nil
            assignments = nil
            assignmentLoadErrorMessage = nil

            Task {
                await loadCanvasClassInfoIfNeeded()
            }
        }
        .sheet(isPresented: $presentAccountPage) {
            NavigationStack {
                AccountView(provider: scheduleInfo.class_.college.provider!)
                    .navigationTitle("\(scheduleInfo.class_.college.provider!.descriptionShort)账户")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("Canvas 错误", isPresented: $showError) {
            if errorDetail == .canvasTokenExpired {
                Button("以后", role: .cancel) { }
                Button("前往设置") {
                    presentAccountPage = true
                }
            }
        } message: {
            switch errorDetail {
            case .canvasTokenExpired:
                Text("无法访问 Canvas，可能是令牌已被删除或重置，请重新启用 Canvas 账户")
            case .none:
                Text("未知错误，请稍候重试")
            }
        }
        .alert("无法保存课程匹配", isPresented: $showCanvasSaveError) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(canvasSaveErrorMessage ?? "请稍后重试")
        }
    }

    private var classInfoPage: some View {
        List {
            if let classRemark {
                Section(header: Text("课程备注")) {
                    Text(classRemark.remark)
                }
            }

            Section(header: Text("基本信息")) {
                CanvasInfoRow(title: "课程代码", value: scheduleInfo.course.code)
                CanvasInfoRow(title: "教学班", value: scheduleInfo.class_.code)
                CanvasInfoRow(title: "教师", value: teacherNames)

                if let remark = scheduleInfo.schedule.remark {
                    CanvasInfoRow(title: "备注", value: remark, multiline: true)
                }
            }

            if isCanvasFeatureAvailable {
                Section {
                    NavigationLink {
                        CanvasCourseSelectionView(
                            selection: canvasSelectionBinding,
                            canvasCourseSections: canvasCourses.groupedByTermSections,
                            isLoading: isLoadingCanvasCourses,
                            loadErrorMessage: canvasCourseLoadErrorMessage,
                            onRetry: {
                                await loadCanvasCoursesIfNeeded(force: true)
                            }
                        )
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Canvas 课程")
                                Text(canvasPickerSubtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Color(UIColor.secondaryLabel))
                                    .lineLimit(2)
                            }

                            Spacer()

                            if isSavingCanvasMatch || (isLoadingCanvasCourses && canvasCourses.isEmpty) {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(canvasToken == nil && canvasClass == nil)
                }

                if canvasClass != nil {
                    Section {
                        NavigationLink {
                            assignmentsPage
                                .navigationTitle("作业")
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("作业", systemImage: "book.pages")
                        }
                    }
                }
            }
        }
    }

    private var canvasSelectionBinding: Binding<String?> {
        Binding(
            get: {
                canvasClass?.id
            },
            set: { newValue in
                let previousValue = canvasClass?.id
                applyCanvasSelectionLocally(newValue)

                Task {
                    await saveCanvasSelection(newValue, previousValue: previousValue)
                }
            }
        )
    }

    private var assignmentsPage: some View {
        ZStack {
            if isLoadingAssignments && assignments == nil {
                CanvasLoadingView(title: "正在加载作业")
            } else if let assignments {
                let items = makeAssignmentItems(from: assignments)

                if items.isEmpty {
                    ContentUnavailableView(
                        "暂无作业",
                        systemImage: "checkmark.circle",
                        description: Text("当前 Canvas 课程没有可显示的作业。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let sections = makeAssignmentSections(from: items)

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
                                        AssignmentListRow(item: item)
                                    }
                                }
                            } header: {
                                AssignmentSectionHeader(section: section)
                            } footer: {
                                if let footer = section.kind.footer {
                                    Text(footer)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .contentMargins(.top, 8, for: .scrollContent)
                    .refreshable {
                        await loadAssignmentsIfNeeded(force: true)
                    }
                }
            } else if let assignmentLoadErrorMessage {
                ContentUnavailableView {
                    Label("无法获取作业", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(assignmentLoadErrorMessage)
                } actions: {
                    if canvasToken == nil {
                        Button("前往设置") {
                            presentAccountPage = true
                        }
                    }

                    Button("重试") {
                        Task {
                            await loadAssignmentsIfNeeded(force: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CanvasLoadingView(title: "正在加载作业")
            }
        }
        .task {
            await loadAssignmentsIfNeeded()
        }
    }

    private func makeAssignmentItems(from assignments: [AssignmentNode]) -> [AssignmentPageItem] {
        assignments.map { assignment in
            let assignmentName = (assignment.name ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let dueDate = assignment.dueAt.flatMap { CanvasFormatters.iso8601.date(from: $0) }
            let latestSubmission = latestSubmission(for: assignment)
            let status: AssignmentPageItem.Status

            if let latestSubmission, latestSubmission.gradingStatus == .graded {
                status = .graded(
                    score: latestSubmission.score,
                    pointsPossible: assignment.pointsPossible
                )
            } else if latestSubmission != nil {
                status = .submitted
            } else if let dueDate {
                status = dueDate < .now ? .overdue : .upcoming
            } else {
                status = .unscheduled
            }

            return AssignmentPageItem(
                assignmentId: assignment.id,
                assignmentName: assignmentName.isEmpty ? "未命名作业" : assignmentName,
                dueDate: dueDate,
                pointsPossible: assignment.pointsPossible,
                status: status
            )
        }
    }

    private func makeAssignmentSections(from items: [AssignmentPageItem]) -> [AssignmentPageSection] {
        let groups = Dictionary(grouping: items, by: \.status.sectionKind)

        return AssignmentPageSection.Kind.allCases.compactMap { kind in
            guard let items = groups[kind], !items.isEmpty else {
                return nil
            }

            return AssignmentPageSection(
                kind: kind,
                items: sortAssignmentItems(items, for: kind)
            )
        }
    }

    private func latestSubmission(for assignment: AssignmentNode) -> AssignmentSubmissionNode? {
        guard let submissions = assignment.submissionsConnection?.nodes else {
            return nil
        }

        return submissions
            .compactMap { $0 }
            .max(by: { $0.attempt < $1.attempt })
    }

    private func sortAssignmentItems(
        _ items: [AssignmentPageItem],
        for kind: AssignmentPageSection.Kind
    ) -> [AssignmentPageItem] {
        items.sorted { lhs, rhs in
            switch kind {
            case .overdue:
                return canvasCompareDates(lhs.dueDate, rhs.dueDate, order: .descending, fallback: lhs.assignmentName < rhs.assignmentName)
            case .upcoming, .submitted:
                return canvasCompareDates(lhs.dueDate, rhs.dueDate, order: .ascending, fallback: lhs.assignmentName < rhs.assignmentName)
            case .graded:
                return canvasCompareDates(lhs.dueDate, rhs.dueDate, order: .descending, fallback: lhs.assignmentName < rhs.assignmentName)
            case .unscheduled:
                return lhs.assignmentName.localizedStandardCompare(rhs.assignmentName) == .orderedAscending
            }
        }
    }

    @MainActor
    private func loadAssignmentsIfNeeded(force: Bool = false) async {
        guard !isLoadingAssignments else {
            return
        }

        if !force && assignments != nil {
            return
        }

        guard let canvasClass else {
            assignmentLoadErrorMessage = "暂时无法确定对应的 Canvas 课程。"
            return
        }

        guard let token = canvasToken else {
            assignmentLoadErrorMessage = "Canvas 令牌不可用，请重新启用账户。"
            return
        }

        isLoadingAssignments = true
        assignmentLoadErrorMessage = nil

        defer {
            isLoadingAssignments = false
        }

        do {
            let client = CanvasAPI(token: token)
            assignments = try await client.getClassAssignments(classId: canvasClass.id)
        } catch ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode {
            assignmentLoadErrorMessage = "Canvas 令牌可能已失效，请重新启用账户。"
            showError = true
            errorDetail = .canvasTokenExpired
        } catch {
            assignmentLoadErrorMessage = "无法获取作业列表，请稍后重试。"
        }
    }

    @MainActor
    private func loadCanvasCoursesIfNeeded(force: Bool = false) async {
        guard let token = canvasToken else {
            canvasCourseLoadErrorMessage = "Canvas 令牌不可用，请重新启用账户"
            return
        }

        if isLoadingCanvasCourses {
            return
        }

        if !force && !canvasCourses.isEmpty {
            return
        }

        isLoadingCanvasCourses = true
        if force {
            canvasCourseLoadErrorMessage = nil
        }

        defer {
            isLoadingCanvasCourses = false
        }

        do {
            let client = CanvasAPI(token: token)
            canvasCourses = try await client.getAllCourseOptions()
            canvasCourseLoadErrorMessage = nil
        } catch ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode {
            canvasCourseLoadErrorMessage = "Canvas 令牌可能已失效，请重新启用账户"
            showError = true
            errorDetail = .canvasTokenExpired
        } catch {
            canvasCourseLoadErrorMessage = "无法加载 Canvas 课程列表"
        }
    }

    @MainActor
    private func applyCanvasSelectionLocally(_ canvasCourseID: String?) {
        if let canvasCourseID {
            canvasClass = CanvasClass(
                id: canvasCourseID,
                college: scheduleInfo.class_.college,
                class_id: scheduleInfo.class_.id
            )
        } else {
            canvasClass = nil
        }
    }

    @MainActor
    private func saveCanvasSelection(_ canvasCourseID: String?, previousValue: String?) async {
        guard previousValue != canvasCourseID else { return }
        guard let pool = Eloquent.pool else {
            canvasSaveErrorMessage = "本地课程数据库尚未初始化，请稍后重试。"
            showCanvasSaveError = true
            await reloadCanvasClass()
            return
        }

        isSavingCanvasMatch = true
        defer {
            isSavingCanvasMatch = false
        }

        do {
            try await pool.write { db in
                try CanvasClass.replaceMatch(
                    canvasCourseID,
                    for: scheduleInfo.class_.id,
                    college: scheduleInfo.class_.college,
                    in: db
                )
            }
            await reloadCanvasClass()
        } catch {
            canvasSaveErrorMessage = "课程匹配保存失败，请稍后重试。"
            showCanvasSaveError = true
            await reloadCanvasClass()
        }
    }

    @MainActor
    private func reloadCanvasClass() async {
        do {
            if let pool = Eloquent.pool {
                canvasClass = try await pool.read { db in
                    try CanvasClass.latestMatch(
                        for: scheduleInfo.class_.id,
                        college: scheduleInfo.class_.college,
                        in: db
                    )
                }
            }
        } catch {
        }
    }

    private func loadClassRemark() async {
        do {
            if let pool = Eloquent.pool {
                let remark = try await pool.read { db in
                    try ClassRemark.filter(
                        Column("college") == scheduleInfo.course.college &&
                        Column("class_id") == scheduleInfo.class_.id
                    ).fetchOne(db)
                }
                withAnimation {
                    classRemark = remark
                }
            }
        } catch {
            print(error)
        }
    }

    private func loadCanvasClassIfNeeded() async {
        guard let token = canvasToken else { return }

        do {
            if let pool = Eloquent.pool {
                let existingCanvasClass = try await pool.read { db in
                    try CanvasClass.latestMatch(
                        for: scheduleInfo.class_.id,
                        college: scheduleInfo.class_.college,
                        in: db
                    )
                }

                if existingCanvasClass == nil {
                    let client = CanvasAPI(token: token)
                    do {
                        let allClasses = try await client.getAllClasses()
                        if let matchedClass = allClasses.first(where: { class_ in
                            if let courseCode = class_.courseCode {
                                return courseCode.contains(scheduleInfo.class_.code)
                            }
                            return false
                        }) {
                            let canvasClass = CanvasClass(id: matchedClass.id, college: scheduleInfo.class_.college, class_id: scheduleInfo.class_.id)
                            try await pool.write { db in
                                try CanvasClass.replaceMatch(
                                    matchedClass.id,
                                    for: scheduleInfo.class_.id,
                                    college: scheduleInfo.class_.college,
                                    in: db
                                )
                            }
                            self.canvasClass = canvasClass
                        }
                    } catch ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode {
                        showError = true
                        errorDetail = .canvasTokenExpired
                    }
                } else {
                    canvasClass = existingCanvasClass
                }
            }
        } catch {
            print(error)
        }
    }

    private func loadCanvasClassInfoIfNeeded() async {
        do {
            if let canvasClass, let token = canvasToken {
                let client = CanvasAPI(token: token)
                canvasClassInfo = try await client.getClass(classId: canvasClass.id)
            }
        } catch {
        }
    }
}

private struct AssignmentPageItem: Identifiable {
    enum Status: Equatable {
        case overdue
        case upcoming
        case submitted
        case graded(score: Double?, pointsPossible: Double?)
        case unscheduled

        var sectionKind: AssignmentPageSection.Kind {
            switch self {
            case .overdue:
                .overdue
            case .upcoming:
                .upcoming
            case .submitted:
                .submitted
            case .graded:
                .graded
            case .unscheduled:
                .upcoming
            }
        }
    }

    let assignmentId: String
    let assignmentName: String
    let dueDate: Date?
    let pointsPossible: Double?
    let status: Status

    var id: String {
        assignmentId
    }
}

private struct AssignmentPageSection: Identifiable {
    enum Kind: CaseIterable, Hashable {
        case overdue
        case upcoming
        case submitted
        case graded
        case unscheduled

        var title: String {
            switch self {
            case .overdue:
                "已逾期"
            case .upcoming:
                "待完成"
            case .submitted:
                "等待评分"
            case .graded:
                "已评分"
            case .unscheduled:
                "未设置截止时间"
            }
        }

        var systemImage: String {
            switch self {
            case .overdue:
                "exclamationmark.circle"
            case .upcoming:
                "calendar.badge.clock"
            case .submitted:
                "paperplane"
            case .graded:
                "checkmark.circle"
            case .unscheduled:
                "clock.badge.questionmark"
            }
        }

        var tint: Color {
            switch self {
            case .overdue:
                .orange
            case .upcoming:
                .blue
            case .submitted:
                .teal
            case .graded:
                .green
            case .unscheduled:
                .secondary
            }
        }

        var footer: String? {
            switch self {
            case .unscheduled:
                "这类作业没有提供截止时间，请以 Canvas 课程页面为准。"
            default:
                nil
            }
        }
    }

    let kind: Kind
    let items: [AssignmentPageItem]

    var id: Kind {
        kind
    }
}

private struct AssignmentSectionHeader: View {
    let section: AssignmentPageSection

    var body: some View {
        CanvasSectionHeader(
            title: section.kind.title,
            subtitle: "\(section.items.count) 项",
            systemImage: section.kind.systemImage,
            tint: section.kind.tint
        )
    }
}

private struct AssignmentListRow: View {
    let item: AssignmentPageItem

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

        if let dueMetadataText {
            items.append(
                CanvasMetadataItem(
                    systemImage: dueSystemImage,
                    text: dueMetadataText
                )
            )
        }

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

    private var dueMetadataText: String? {
        guard let dueDate = item.dueDate else {
            if case .unscheduled = item.status {
                return "未设置截止时间"
            }
            return nil
        }

        return dueDate.formattedCanvasAbsoluteDate()
    }

    private var dueSystemImage: String {
        switch item.status {
        case .overdue:
            "clock"
        default:
            "calendar"
        }
    }
}

private extension AssignmentPageItem.Status {
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
            CanvasStatusPresentation(title: "待完成", tint: .secondary)
        }
    }
}
