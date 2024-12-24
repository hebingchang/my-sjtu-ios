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
    var scheduleInfo: ScheduleInfo
    
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @State private var page: Int = 0
    @State private var classRemark: ClassRemark?
    @State private var canvasClass: CanvasClass?
    @State private var canvasClassInfo: CanvasSchema.GetClassQuery.Data.Course?
    @State private var assignments: [CanvasSchema.GetClassAssignmentsQuery.Data.Course.AssignmentsConnection.Node]?
    @State private var canvasError: APIError?
    @State private var showError: Bool = false
    @State private var presentAccountPage: Bool = false
    @State private var errorDetail: ClassViewError?
    @State private var syllabusText: AttributedString?

    private enum ClassViewError: Error {
        case canvasTokenExpired
    }

    var body: some View {
        let account = accounts.first {
            $0.provider == .jaccount
        }

        VStack {
            if page == 0 {
                List {
                    if let classRemark {
                        Section(header: Text("课程备注")) {
                            Text(classRemark.remark)
                        }
                    }
                    
                    Section(header: Text("基本信息")) {
                        HStack {
                            Text("课程代码")
                            Spacer()
                            Text(scheduleInfo.course.code)
                                .font(.callout)
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                        }
                        HStack {
                            Text("教学班")
                            Spacer()
                            Text(scheduleInfo.class_.code)
                                .font(.callout)
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                        }
                        HStack {
                            Text("教师")
                            Spacer()
                            if let teachers = scheduleInfo.schedule.teachers, teachers.count > 0 {
                                Text(teachers.joined(separator: "、"))
                                    .font(.callout)
                                    .foregroundStyle(Color(UIColor.secondaryLabel))
                            } else {
                                Text(scheduleInfo.class_.teachers.joined(separator: "、"))
                                    .font(.callout)
                                    .foregroundStyle(Color(UIColor.secondaryLabel))
                            }
                        }
                        if let remark = scheduleInfo.schedule.remark {
                            HStack {
                                Text("备注")
                                Spacer()
                                Text(remark)
                                    .font(.callout)
                                    .foregroundStyle(Color(UIColor.secondaryLabel))
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    
                    if let syllabusText {
                        Section(header: Text("课程大纲")) {
                            Text(syllabusText)
                        }
                    }
                }
                .animation(.easeInOut, value: syllabusText)
            }
            
            if page == 1 {
                Group {
                    if let assignments {
                        let dateFormatter = ISO8601DateFormatter()
                        
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
                        
                        let sections: [(String, [CanvasSchema.GetClassAssignmentsQuery.Data.Course.AssignmentsConnection.Node])] = [
                            ("未标注日期的作业", nodue),
                            ("进行中的作业", upcoming),
                            ("过去的作业", history)
                        ].filter { !$0.1.isEmpty }
                        
                        List {
                            ForEach(sections, id: \.0) { (section, assignments) in
                                Section(header: Text(section)) {
                                    ForEach(assignments, id: \.id) { assignment in
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
                    do {
                        if let canvasClass {
                            if let account, account.enabledFeatures.contains(.canvas), account.bizData["canvas_token"] != nil {
                                let client = CanvasAPI(token: account.bizData["canvas_token"]!)
                                self.assignments = try await client.getClassAssignments(classId: canvasClass.id)
                            }
                        }
                    } catch {
                        canvasError = .internalError
                    }
                }
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
            do {
                if let pool = Eloquent.pool {
                    let remark = try await pool.read { db in
                        try ClassRemark.filter(
                            Column("college") == scheduleInfo.course.college &&
                            Column("class_id") == scheduleInfo.class_.id
                        ).fetchOne(db)
                    }
                    withAnimation {
                        self.classRemark = remark
                    }
                }
            } catch {
                print(error)
            }
        }
        .task {
            if let account, account.enabledFeatures.contains(.canvas), account.bizData["canvas_token"] != nil {
                do {
                    // if class exists on canvas lms
                    if let pool = Eloquent.pool {
                        let canvasClass = try await pool.read { db in
                            try CanvasClass.filter(
                                Column("college") == scheduleInfo.course.college &&
                                Column("class_id") == scheduleInfo.class_.id
                            ).fetchOne(db)
                        }
                        
                        if canvasClass == nil {
                            let client = CanvasAPI(token: account.bizData["canvas_token"]!)
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
                                // maybe 401
                                showError = true
                                errorDetail = .canvasTokenExpired
                            }
                        } else {
                            self.canvasClass = canvasClass
                        }
                    }
                } catch {
                    print(error)
                }
            }
        }
        .onChange(of: canvasClass) {
            Task {
                do {
                    if let canvasClass {
                        if let account, account.enabledFeatures.contains(.canvas), account.bizData["canvas_token"] != nil {
                            let client = CanvasAPI(token: account.bizData["canvas_token"]!)
                            self.canvasClassInfo = try await client.getClass(classId: canvasClass.id)
                            
                            DispatchQueue.main.async {
                                if let syllabus = canvasClassInfo?.syllabusBody {
                                    if let data = syllabus.data(using: .utf8) {
                                        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                                            .documentType: NSAttributedString.DocumentType.html,
                                            .characterEncoding: String.Encoding.utf8.rawValue
                                        ]
                                        if let syllabusBody = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                                            self.syllabusText = try? AttributedString(syllabusBody, including: \.uiKit)
                                            self.syllabusText?.foregroundColor = UIColor.label
                                            self.syllabusText?.font = UIFont.preferredFont(forTextStyle: .callout)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    
                }
            }
        }
        .sheet(isPresented: $presentAccountPage) {
            NavigationStack {
                AccountView(provider: scheduleInfo.class_.college.provider!)
                    .navigationTitle("\(scheduleInfo.class_.college.provider!.descriptionShort)账户")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("Canvas 错误", isPresented: $showError, presenting: errorDetail) { detail in
            if detail == .canvasTokenExpired {
                Button("以后", role: .cancel) { }
                Button("前往设置") {
                    presentAccountPage = true
                }
            }
        } message: { detail in
            switch detail {
            case .canvasTokenExpired:
                Text("无法访问 Canvas，可能是令牌已被删除或重置，请重新启用 Canvas 账户")
            }
        }
    }
}
