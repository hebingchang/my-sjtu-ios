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
    private typealias AssignmentSections = [(String, [AssignmentNode])]

    var scheduleInfo: ScheduleInfo

    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @State private var page: Int = 0
    @State private var classRemark: ClassRemark?
    @State private var canvasClass: CanvasClass?
    @State private var canvasClassInfo: CanvasSchema.GetClassQuery.Data.Course?
    @State private var assignments: [AssignmentNode]?
    @State private var canvasError: APIError?
    @State private var showError: Bool = false
    @State private var presentAccountPage: Bool = false
    @State private var errorDetail: ClassViewError?

    private enum ClassViewError: Error {
        case canvasTokenExpired
    }

    private var account: WebAuthAccount? {
        accounts.first { $0.provider == .jaccount }
    }

    private var canvasToken: String? {
        guard let account,
              account.enabledFeatures.contains(.canvas),
              let token = account.bizData["canvas_token"]
        else {
            return nil
        }
        return token
    }

    private var teacherNames: String {
        if let teachers = scheduleInfo.schedule.teachers, teachers.count > 0 {
            return teachers.joined(separator: "、")
        }
        return scheduleInfo.class_.teachers.joined(separator: "、")
    }

    var body: some View {
        VStack {
            if page == 0 {
                classInfoPage
            }

            if page == 1 {
                assignmentsPage
            }
        }
        .animation(.easeInOut, value: page)
        .animation(.easeInOut, value: assignments)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("页面", selection: $page) {
                    Text("课程信息").tag(0)
                    if canvasClass != nil {
                        Text("作业").tag(1)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        .task {
            await loadClassRemark()
        }
        .task {
            await loadCanvasClassIfNeeded()
        }
        .onChange(of: canvasClass) {
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
    }

    private var classInfoPage: some View {
        List {
            if let classRemark {
                Section(header: Text("课程备注")) {
                    Text(classRemark.remark)
                }
            }

            Section(header: Text("基本信息")) {
                infoRow(title: "课程代码", value: scheduleInfo.course.code)
                infoRow(title: "教学班", value: scheduleInfo.class_.code)
                infoRow(title: "教师", value: teacherNames)

                if let remark = scheduleInfo.schedule.remark {
                    infoRow(title: "备注", value: remark, multiline: true)
                }
            }
        }
    }

    @ViewBuilder
    private var assignmentsPage: some View {
        Group {
            if let assignments {
                let dateFormatter = ISO8601DateFormatter()
                let sections = makeAssignmentSections(from: assignments, dateFormatter: dateFormatter)

                List {
                    ForEach(sections, id: \.0) { (section, assignments) in
                        Section(header: Text(section)) {
                            ForEach(assignments, id: \.id) { assignment in
                                NavigationLink {
                                    CanvasAssignmentView(assignmentId: assignment.id, assignmentName: assignment.name ?? "")
                                } label: {
                                    assignmentRow(assignment, dateFormatter: dateFormatter)
                                }
                            }
                        }
                    }
                }
            } else if let canvasError {
                switch canvasError {
                default:
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                            .font(.system(size: 64))
                        Text("无法获取作业列表")
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack {
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .task {
            await loadAssignmentsIfNeeded()
        }
    }

    private func infoRow(title: String, value: String, multiline: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundStyle(Color(UIColor.secondaryLabel))
                .multilineTextAlignment(multiline ? .trailing : .leading)
        }
    }

    private func assignmentRow(_ assignment: AssignmentNode, dateFormatter: ISO8601DateFormatter) -> some View {
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

    private func makeAssignmentSections(from assignments: [AssignmentNode], dateFormatter: ISO8601DateFormatter) -> AssignmentSections {
        let nodue = assignments.filter { assignment in
            assignment.dueAt == nil
        }.sorted {
            $0.id > $1.id
        }

        let upcoming = assignments.filter { assignment in
            if let dueAt = assignment.dueAt {
                let date = dateFormatter.date(from: dueAt)!
                return date >= Date()
            } else {
                return false
            }
        }.sorted {
            $0.dueAt == $1.dueAt ? ($0.id > $1.id) : dateFormatter.date(from: $0.dueAt!)! > dateFormatter.date(from: $1.dueAt!)!
        }

        let history = assignments.filter { assignment in
            if let dueAt = assignment.dueAt {
                let date = dateFormatter.date(from: dueAt)!
                return date < Date()
            } else {
                return false
            }
        }.sorted {
            $0.dueAt == $1.dueAt ? ($0.id > $1.id) : dateFormatter.date(from: $0.dueAt!)! > dateFormatter.date(from: $1.dueAt!)!
        }

        return [
            ("未标注日期的作业", nodue),
            ("进行中的作业", upcoming),
            ("过去的作业", history),
        ].filter { !$0.1.isEmpty }
    }

    private func loadAssignmentsIfNeeded() async {
        do {
            if let canvasClass, let token = canvasToken {
                let client = CanvasAPI(token: token)
                assignments = try await client.getClassAssignments(classId: canvasClass.id)
            }
        } catch {
            canvasError = .internalError
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
                    try CanvasClass.filter(
                        Column("college") == scheduleInfo.course.college &&
                        Column("class_id") == scheduleInfo.class_.id
                    ).fetchOne(db)
                }

                if existingCanvasClass == nil {
                    let client = CanvasAPI(token: token)
                    do {
                        for class_ in try await client.getAllClasses() {
                            if let courseCode = class_.courseCode, courseCode.contains(scheduleInfo.class_.code) {
                                let canvasClass = CanvasClass(id: class_.id, college: scheduleInfo.class_.college, class_id: scheduleInfo.class_.id)
                                try await pool.write { db in
                                    try canvasClass.save(db)
                                }
                                self.canvasClass = canvasClass
                            }
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
