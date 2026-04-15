//
//  CanvasSettingsView.swift
//  MySJTU
//
//  Created by boar on 2026/03/28.
//

import SwiftUI
import GRDB
import Apollo
import UIKit

struct CanvasSettingsView: View {
    @AppStorage("accounts") private var accounts: [WebAuthAccount] = []
    @State private var showCopyTokenConfirmation = false
    @State private var showCopySuccessAlert = false

    private var canvasToken: String? {
        accounts.jaccountCanvasToken
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    CanvasCourseMatchingSettingsView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("课程匹配")
                        Text("由于 Canvas LMS 系统限制，课表课程偶尔会出现无法与 Canvas 课程匹配的情况。如遇到这种情况，请进入本设置进行手动匹配。")
                            .font(.footnote)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Button {
                    showCopyTokenConfirmation = true
                } label: {
                    Label("复制 Canvas 令牌", systemImage: "document.on.doc")
                }
                .disabled(canvasToken == nil)
                .confirmationDialog("复制 Canvas 令牌", isPresented: $showCopyTokenConfirmation, titleVisibility: .visible) {
                    Button("复制令牌") {
                        copyCanvasToken()
                    }
                    Button("取消", role: .cancel) {
                    }
                } message: {
                    Text("Canvas 令牌相当于您的账户访问凭证，请不要提供给不受信任的第三方。")
                }
            } header: {
                Text("Canvas 令牌")
            } footer: {
                if canvasToken == nil {
                    Text("当前没有可复制的 Canvas 令牌，请先在账户设置中启用 Canvas。")
                } else {
                    Text("如果您有使用不同 Apple ID 登录的设备，可以通过手动输入 Canvas 令牌来启用 Canvas 功能。")
                }
            }
        }
        .analyticsScreen(
            "canvas_settings",
            screenClass: "CanvasSettingsView",
            parameters: [
                "has_token": canvasToken != nil
            ]
        )
        .navigationTitle("Canvas")
        .navigationBarTitleDisplayMode(.inline)
        .alert("已复制 Canvas 令牌", isPresented: $showCopySuccessAlert) {
            Button("知道了", role: .cancel) {
            }
        } message: {
            Text("Canvas 令牌已复制到剪贴板。")
        }
    }

    private func copyCanvasToken() {
        guard let canvasToken else {
            return
        }

        UIPasteboard.general.string = canvasToken
        AnalyticsService.logEvent(
            "canvas_token_copied",
            parameters: [
                "has_token": true
            ]
        )
        showCopySuccessAlert = true
    }
}

struct CanvasCourseMatchingSettingsView: View {
    private let canvasColleges: [College] = [.sjtu, .sjtug, .joint]

    @AppStorage("accounts") private var accounts: [WebAuthAccount] = []
    @AppStorage("collegeId", store: UserDefaults.shared) private var collegeId: College = .sjtu
    @State private var localCourses: [LocalCanvasCourse] = []
    @State private var canvasCourses: [CanvasCourseOption] = []
    @State private var isLoading = true
    @State private var loadErrorMessage: String?
    @State private var saveErrorMessage: String?
    @State private var showSaveError = false
    @State private var savingCourseIDs: Set<String> = []
    @State private var showTokenExpiredAlert: Bool = false
    @State private var presentAccountPage: Bool = false

    private var canvasToken: String? {
        accounts.jaccountCanvasToken
    }

    private var displayedCollege: College {
        switch collegeId {
        case .sjtu:
            return .sjtu
        case .joint:
            return .joint
        default:
            return .sjtu
        }
    }

    private var filteredLocalCourses: [LocalCanvasCourse] {
        localCourses.filter { $0.college == displayedCollege }
    }

    private var semesterSections: [LocalCanvasCourseSemesterSection] {
        let grouped = Dictionary(grouping: filteredLocalCourses, by: \.semesterGroupID)
        let orderedSemesterIDs = filteredLocalCourses.reduce(into: [String]()) { result, course in
            if !result.contains(course.semesterGroupID) {
                result.append(course.semesterGroupID)
            }
        }

        return orderedSemesterIDs.compactMap { semesterID in
            guard let courses = grouped[semesterID], let firstCourse = courses.first else {
                return nil
            }

            return LocalCanvasCourseSemesterSection(
                id: semesterID,
                title: firstCourse.semesterTitle,
                courses: courses
            )
        }
    }

    var body: some View {
        Group {
            if isLoading && localCourses.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadErrorMessage {
                ContentUnavailableView(
                    "无法加载课程匹配",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadErrorMessage)
                )
            } else if filteredLocalCourses.isEmpty {
                ContentUnavailableView(
                    "暂无本地课程",
                    systemImage: "books.vertical",
                    description: Text("当前数据源下暂无可用于匹配的本地课程。")
                )
            } else {
                List {
                    ForEach(semesterSections) { section in
                        Section(header: Text(section.title)) {
                            ForEach(section.courses) { course in
                                CanvasCourseMatchRow(
                                    course: course,
                                    currentCanvasCourseSummary: currentCanvasCourseSummary(for: course),
                                    canvasCourseSections: canvasCourses.groupedByTermSections,
                                    isSaving: savingCourseIDs.contains(course.id),
                                    selection: selectionBinding(for: course)
                                )
                            }
                        }
                    }
                }
                .refreshable {
                    await loadData(force: true)
                }
            }
        }
        .analyticsScreen(
            "canvas_course_matching",
            screenClass: "CanvasCourseMatchingSettingsView",
            parameters: [
                "local_course_count": filteredLocalCourses.count,
                "canvas_course_count": canvasCourses.count
            ]
        )
        .navigationTitle("课程匹配")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadData()
        }
        .onChange(of: displayedCollege) {
            Task {
                await autoMatchDisplayedCoursesIfNeeded()
            }
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
        .alert("无法保存课程匹配", isPresented: $showSaveError) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(saveErrorMessage ?? "请稍后重试。")
        }
    }

    private func selectionBinding(for course: LocalCanvasCourse) -> Binding<String?> {
        Binding(
            get: {
                localCourses.first(where: { $0.id == course.id })?.canvasCourseID
            },
            set: { newValue in
                let previousValue = localCourses.first(where: { $0.id == course.id })?.canvasCourseID
                applyLocalSelection(newValue, for: course.id)

                Task {
                    await saveSelection(newValue, previousValue: previousValue, for: course)
                }
            }
        )
    }

    @MainActor
    private func loadData(force: Bool = false) async {
        if !force && (!localCourses.isEmpty || loadErrorMessage != nil) {
            isLoading = false
            return
        }

        if localCourses.isEmpty {
            isLoading = true
        }
        loadErrorMessage = nil

        do {
            let localCourses = try await fetchLocalCourses()
            let canvasCourses = try await fetchCanvasCourses()
            let didAutoMatch = try await autoMatchDisplayedCoursesIfNeeded(
                localCourses: localCourses,
                canvasCourses: canvasCourses
            )

            self.canvasCourses = canvasCourses
            self.localCourses = didAutoMatch ? try await fetchLocalCourses() : localCourses
        } catch ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode {
            loadErrorMessage = "Canvas 令牌可能已失效，请前往账户设置重新启用 Canvas。"
            showTokenExpiredAlert = true
        } catch APIError.noAccount {
            loadErrorMessage = "未找到可用的 Canvas 账户，请先在设置中启用 Canvas。"
        } catch EloquentError.dbNotOpened {
            loadErrorMessage = "本地课程数据库尚未初始化，请稍后重试。"
        } catch {
            loadErrorMessage = "由于未知错误，暂时无法加载课程匹配。"
        }

        isLoading = false
    }

    @MainActor
    private func autoMatchDisplayedCoursesIfNeeded() async {
        guard !localCourses.isEmpty, !canvasCourses.isEmpty else {
            return
        }

        do {
            let didAutoMatch = try await autoMatchDisplayedCoursesIfNeeded(
                localCourses: localCourses,
                canvasCourses: canvasCourses
            )

            if didAutoMatch {
                localCourses = try await fetchLocalCourses()
            }
        } catch {
        }
    }

    private func autoMatchDisplayedCoursesIfNeeded(
        localCourses: [LocalCanvasCourse],
        canvasCourses: [CanvasCourseOption]
    ) async throws -> Bool {
        guard let pool = Eloquent.pool else {
            throw EloquentError.dbNotOpened
        }

        let displayedCourses = localCourses.filter { $0.college == displayedCollege }
        var usedCanvasCourseIDs = Set(displayedCourses.compactMap(\.canvasCourseID))
        var collectedMatches: [(canvasCourseID: String, localCourse: LocalCanvasCourse)] = []

        for course in displayedCourses where course.canvasCourseID == nil {
            if let matchedCourse = canvasCourses.first(where: { canvasCourse in
                guard !usedCanvasCourseIDs.contains(canvasCourse.id),
                      let courseCode = canvasCourse.courseCode
                else {
                    return false
                }

                return courseCode.contains(course.classCode)
            }) {
                usedCanvasCourseIDs.insert(matchedCourse.id)
                collectedMatches.append((canvasCourseID: matchedCourse.id, localCourse: course))
            }
        }

        guard !collectedMatches.isEmpty else {
            return false
        }

        let pendingMatches = collectedMatches
        try await pool.write { db in
            for match in pendingMatches {
                try CanvasClass.replaceMatch(
                    match.canvasCourseID,
                    for: match.localCourse.classID,
                    college: match.localCourse.college,
                    in: db
                )
            }
        }

        return true
    }

    private func currentCanvasCourseSummary(for course: LocalCanvasCourse) -> String {
        guard let canvasCourseID = course.canvasCourseID else {
            return "尚未匹配到 Canvas 课程"
        }

        if let canvasCourse = canvasCourses.idDictionary[canvasCourseID] {
            return "已匹配到 \(canvasCourse.name)"
        }

        return "已匹配到一个当前不可用的 Canvas 课程"
    }

    private func applyLocalSelection(_ canvasCourseID: String?, for localCourseID: String) {
        for index in localCourses.indices {
            if localCourses[index].id == localCourseID {
                localCourses[index].canvasCourseID = canvasCourseID
            } else if let canvasCourseID, localCourses[index].canvasCourseID == canvasCourseID {
                localCourses[index].canvasCourseID = nil
            }
        }
    }

    @MainActor
    private func saveSelection(_ canvasCourseID: String?, previousValue: String?, for course: LocalCanvasCourse) async {
        guard previousValue != canvasCourseID else { return }
        guard let pool = Eloquent.pool else {
            saveErrorMessage = "本地课程数据库尚未初始化，请稍后重试。"
            showSaveError = true
            await reloadLocalCourses()
            return
        }

        savingCourseIDs.insert(course.id)
        defer {
            savingCourseIDs.remove(course.id)
        }

        do {
            try await pool.write { db in
                try CanvasClass.replaceMatch(canvasCourseID, for: course.classID, college: course.college, in: db)
            }
            await reloadLocalCourses()
        } catch {
            saveErrorMessage = "课程匹配保存失败，请稍后重试。"
            showSaveError = true
            await reloadLocalCourses()
        }
    }

    @MainActor
    private func reloadLocalCourses() async {
        do {
            localCourses = try await fetchLocalCourses()
        } catch {
        }
    }

    private func fetchLocalCourses() async throws -> [LocalCanvasCourse] {
        guard let pool = Eloquent.pool else {
            throw EloquentError.dbNotOpened
        }

        return try await pool.read { db in
            let semesters = try Semester
                .filter(canvasColleges.contains(Column("college")))
                .fetchAll(db)
            let classes = try Class
                .filter(canvasColleges.contains(Column("college")))
                .fetchAll(db)
            let courses = try Course
                .filter(canvasColleges.contains(Column("college")))
                .fetchAll(db)
            let mappings = try CanvasClass
                .filter(canvasColleges.contains(Column("college")))
                .fetchAll(db)

            let semesterByID = Dictionary(uniqueKeysWithValues: semesters.map { (Self.semesterStorageKey(id: $0.id, college: $0.college), $0) })
            let courseByID = Dictionary(uniqueKeysWithValues: courses.map { (Self.courseStorageKey(code: $0.code, college: $0.college), $0) })
            let mappingByClassID = mappings.reduce(into: [String: CanvasClass]()) { result, mapping in
                result[Self.classStorageKey(id: mapping.class_id, college: mapping.college)] = mapping
            }

            return classes.compactMap { class_ in
                guard let semester = semesterByID[Self.semesterStorageKey(id: class_.semester_id, college: class_.college)] else {
                    return nil
                }

                let course = courseByID[Self.courseStorageKey(code: class_.course_code, college: class_.college)]
                let mapping = mappingByClassID[Self.classStorageKey(id: class_.id, college: class_.college)]

                return LocalCanvasCourse(
                    classID: class_.id,
                    college: class_.college,
                    courseName: course?.name ?? class_.name,
                    classCode: class_.code,
                    semesterTitle: Self.semesterDisplayTitle(for: semester),
                    semesterGroupID: Self.semesterStorageKey(id: semester.id, college: semester.college),
                    semesterStartAt: semester.start_at,
                    canvasCourseID: mapping?.id
                )
            }
            .sorted { lhs, rhs in
                if lhs.semesterStartAt != rhs.semesterStartAt {
                    return lhs.semesterStartAt > rhs.semesterStartAt
                }
                if lhs.courseName != rhs.courseName {
                    return lhs.courseName.localizedCompare(rhs.courseName) == .orderedAscending
                }
                return lhs.classCode.localizedCompare(rhs.classCode) == .orderedAscending
            }
        }
    }

    private func fetchCanvasCourses() async throws -> [CanvasCourseOption] {
        guard let canvasToken else {
            throw APIError.noAccount
        }

        let api = CanvasAPI(token: canvasToken)
        return try await api.getAllCourseOptions()
    }

    nonisolated private static func semesterDisplayTitle(for semester: Semester) -> String {
        if let name = semester.name, !name.isEmpty {
            return name
        }

        let seasonName = switch semester.semester {
        case 1: "秋"
        case 2: "春"
        case 3: "夏"
        default: "未知"
        }

        return "\(semester.year) 学年\(seasonName)季学期"
    }

    nonisolated private static func semesterStorageKey(id: String, college: College) -> String {
        "\(college.rawValue)-\(id)"
    }

    nonisolated private static func courseStorageKey(code: String, college: College) -> String {
        "\(college.rawValue)-\(code)"
    }

    nonisolated private static func classStorageKey(id: String, college: College) -> String {
        "\(college.rawValue)-\(id)"
    }
}

private struct CanvasCourseMatchRow: View {
    let course: LocalCanvasCourse
    let currentCanvasCourseSummary: String
    let canvasCourseSections: [CanvasCourseTermSection]
    let isSaving: Bool
    @Binding var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.courseName)
                        .fontWeight(.medium)
                    Text(course.classCode)
                        .font(.footnote)
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                }

                Spacer()

                CanvasMatchStatusBadge(isMatched: selection != nil, isSaving: isSaving)
            }

            NavigationLink {
                CanvasCourseSelectionView(
                    selection: $selection,
                    canvasCourseSections: canvasCourseSections
                )
            } label: {
                Text(currentCanvasCourseSummary)
                    .font(.footnote)
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                    .lineLimit(1)
            }
            .disabled(isSaving)
        }
        .padding(.vertical, 4)
    }
}

private struct CanvasMatchStatusBadge: View {
    let isMatched: Bool
    let isSaving: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            }

            Image(systemName: isMatched ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(isMatched ? Color.green : Color(UIColor.secondaryLabel))

            Text(isMatched ? "已匹配" : "未匹配")
                .font(.caption)
                .foregroundStyle(Color(UIColor.secondaryLabel))
        }
    }
}

private struct LocalCanvasCourse: Identifiable, Equatable {
    var id: String { "\(college.rawValue)-\(classID)" }

    let classID: String
    let college: College
    let courseName: String
    let classCode: String
    let semesterTitle: String
    let semesterGroupID: String
    let semesterStartAt: Date
    var canvasCourseID: String?
}

private struct LocalCanvasCourseSemesterSection: Identifiable {
    let id: String
    let title: String
    let courses: [LocalCanvasCourse]
}

#Preview {
    NavigationStack {
        CanvasSettingsView()
    }
}
