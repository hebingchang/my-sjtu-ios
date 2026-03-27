//
//  ExamView.swift
//  MySJTU
//
//  Created by boar on 2025/01/05.
//

import SwiftUI
import GRDBQuery

struct ExamView: View {
    @State private var loading: Bool = true
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @Query<SemestersRequest> private var availableSemesters: [Semester]
    @State private var selectedSemester: Semester?
    @State private var exams: [ElectSysAPI.Exam] = []
    @State private var grades: [ElectSysAPI.Grade] = []
    @AppStorage("exam.shownGrades") var shownGrades: [String] = []

    init() {
        _availableSemesters = Query(constant: SemestersRequest(college: .sjtu))
    }

    var body: some View {
        let account = accounts.first {
            $0.provider == .jaccount
        }
        let horizontalContentPadding: CGFloat = 16
        
        ZStack {
            LinearGradient(
                colors: [
                    Color(UIColor.systemGroupedBackground),
                    Color(UIColor.secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if loading {
                VStack {
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if exams.isEmpty && grades.isEmpty {
                ContentUnavailableView("暂无考试与成绩", systemImage: "calendar.badge.exclamationmark", description: Text("请尝试切换学期查看。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    let noDate = exams.filter { exam in
                        exam.start == nil || exam.end == nil
                    }
                    let upcoming = exams.filter { exam in
                        exam.start != nil && exam.start! > .now
                    }.sorted(by: { $0.start! < $1.start! })
                    let ongoing = exams.filter { exam in
                        exam.start != nil && exam.end != nil && exam.start! <= .now && exam.end! >= .now
                    }.sorted(by: { $0.start! < $1.start! })
                    let history = exams.filter { exam in
                        exam.end != nil && exam.end! < .now
                    }
                    let shownGradeCount = grades.reduce(into: 0) { result, grade in
                        if shownGrades.contains(grade.id) {
                            result += 1
                        }
                    }
                    
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                OverviewCard(
                                    title: "进行中",
                                    value: "\(ongoing.count)",
                                    systemImage: "timer",
                                    tint: .orange
                                )

                                OverviewCard(
                                    title: "即将开始",
                                    value: "\(upcoming.count)",
                                    systemImage: "calendar.badge.clock",
                                    tint: .blue
                                )

                                OverviewCard(
                                    title: "已出成绩",
                                    value: "\(grades.count)",
                                    systemImage: "graduationcap",
                                    tint: .mint
                                )
                            }
                            .padding(.horizontal, horizontalContentPadding)
                            .padding(.vertical, 4)
                        }
                        .padding(.horizontal, -horizontalContentPadding)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    if ongoing.count > 0 {
                        Section(header: SectionHeaderView(title: "正在进行的考试", subtitle: "\(ongoing.count) 场", systemImage: "timer", tint: .orange)) {
                            ForEach(ongoing, id: \.code) { exam in
                                ExamRow(exam: exam)
                            }
                        }
                    }
                    
                    if upcoming.count > 0 {
                        Section(header: SectionHeaderView(title: "即将进行的考试", subtitle: "\(upcoming.count) 场", systemImage: "calendar", tint: .blue), footer: Text("考试信息仅供参考。实际考试时间与地点以教学信息服务网为准。")) {
                            ForEach(upcoming, id: \.code) { exam in
                                ExamRow(exam: exam)
                            }
                        }
                    }
                    
                    var showsShowAllGrades: Bool {
                        return grades.first { !shownGrades.contains($0.id) } != nil
                    }
                    
                    Section(header: HStack(spacing: 10) {
                        SectionHeaderIcon(systemImage: "graduationcap.fill", tint: .mint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("成绩")
                                .font(.headline)
                            Text("已显示 \(shownGradeCount)/\(grades.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if grades.count > 0 {
                            GradeVisibilityToggleButton(showAll: showsShowAllGrades) {
                                if showsShowAllGrades {
                                    var newGrades: [String] = []
                                    for grade in grades {
                                        if !shownGrades.contains(grade.id) {
                                            newGrades.append(grade.id)
                                        }
                                    }
                                    withAnimation {
                                        shownGrades.append(contentsOf: newGrades)
                                    }
                                } else {
                                    withAnimation {
                                        shownGrades.removeAll { g in grades.first { $0.id == g } != nil }
                                    }
                                }
                            }
                        }
                    }) {
                        if grades.count > 0 {
                            ForEach(grades, id: \.courseCode) { grade in
                                GradeRow(grade: grade, semester: selectedSemester!)
                            }
                        } else {
                            Text("暂无成绩")
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if history.count > 0 {
                        Section(header: SectionHeaderView(title: "已结束的考试", subtitle: "\(history.count) 场", systemImage: "checkmark.circle", tint: .green)) {
                            ForEach(history, id: \.code) { exam in
                                ExamRow(exam: exam)
                            }
                        }
                    }
                    
                    if noDate.count > 0 {
                        Section(header: SectionHeaderView(title: "未设置时间的考试", subtitle: "\(noDate.count) 场", systemImage: "questionmark.circle", tint: .secondary)) {
                            ForEach(noDate, id: \.code) { exam in
                                ExamRow(exam: exam)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, horizontalContentPadding, for: .scrollContent)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: availableSemesters, initial: true) {
            for semester in availableSemesters {
                if semester.start_at < .now {
                    selectedSemester = semester
                    break
                }
            }
        }
        .onChange(of: selectedSemester) {
            if let selectedSemester {
                loading = true
                Task {
                    do {
                        if let account, account.enabledFeatures.contains(.examAndGrade) {
                            let api = ElectSysAPI(cookies: account.cookies.map { $0.httpCookie! })
                            try await api.openIdConnect()
                            exams = try await api.getExams(year: selectedSemester.year, semester: selectedSemester.semester)
                            grades = try await api.getGrades(year: selectedSemester.year, semester: selectedSemester.semester)
                        }
                        loading = false
                    } catch {
                        print(error)
                        loading = false
                    }
                }
            }
        }
        .animation(.easeInOut, value: loading)
        .toolbar {
            if let selectedSemester {
                ToolbarItem(placement: .principal) {
                    var semesterLabel: String {
                        return "\(selectedSemester.year) 学年\(["秋", "春", "夏"][selectedSemester.semester - 1])季学期"
                    }

                    HStack(spacing: 0) {
                        Menu {
                            Button("当前学期") {
                                for semester in availableSemesters {
                                    if semester.start_at < .now {
                                        self.selectedSemester = semester
                                        break
                                    }
                                }
                            }
                            
                            Divider()
                            
                            ForEach(Array(Set(availableSemesters.map(\.year))).sorted(by: { $0 > $1 }), id: \.self) { year in
                                Menu {
                                    ForEach(availableSemesters.filter { $0.year == year }, id: \.id) { semester in
                                        Button {
                                            self.selectedSemester = semester
                                        } label: {
                                            let desc = "\(semester.start_at.formatted(format: "yy/M")) ~ \(semester.end_at.formatted(format: "yy/M"))"
                                            
                                            HStack {
                                                Text("\(["秋", "春", "夏"][semester.semester - 1])季学期 (\(desc))")
                                                if selectedSemester.id == semester.id {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    Text("\(String(year)) 学年")
                                }
                            }
                        } label: {
                            HStack {
                                Text(semesterLabel)
                                Image(systemName: "chevron.up.chevron.down")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                            }
                            .foregroundStyle(Color(UIColor.label))
                            .fontWeight(.medium)
                        }
                    }
                }
            }
        }
    }

    struct OverviewCard: View {
        let title: String
        let value: String
        let systemImage: String
        let tint: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(UIColor.label))
            }
            .frame(minWidth: 112, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.22), lineWidth: 1)
            )
        }
    }

    struct SectionHeaderIcon: View {
        let systemImage: String
        let tint: Color

        var body: some View {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 28, height: 28)
        }
    }

    struct SectionHeaderView: View {
        let title: String
        let subtitle: String
        let systemImage: String
        let tint: Color

        var body: some View {
            HStack(spacing: 10) {
                SectionHeaderIcon(systemImage: systemImage, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    struct GradeVisibilityToggleButton: View {
        let showAll: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(showAll ? Color.mint.opacity(0.2) : Color.secondary.opacity(0.15))
                        Image(systemName: showAll ? "eye" : "eye.slash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(showAll ? Color.mint : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 22, height: 22)

                    Text(showAll ? "显示全部" : "隐藏全部")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(UIColor.label))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule()
                        .stroke(showAll ? Color.mint.opacity(0.35) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .accessibilityLabel(showAll ? "显示全部成绩" : "隐藏全部成绩")
        }
    }
    
    struct GradeRow: View {
        let grade: ElectSysAPI.Grade
        let semester: Semester
        @AppStorage("exam.shownGrades") var shownGrades: [String] = []
        @State var showGradeScratchSheet: Bool = false
        @State var showGradeGuessSheet: Bool = false

        var body: some View {
            let showGrade = shownGrades.contains(grade.id)
            let firstLine = grade.grade ?? grade.remark ?? grade.score
            let secondLine = (!showGrade || (grade.grade == nil && grade.remark == nil)) ? "" : grade.score
            
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(grade.courseName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        MetaPill(systemImage: "person.fill", text: grade.teacher)
                        MetaPill(systemImage: "number.square.fill", text: "\(grade.credit)学分")
                    }
                }
                
                Spacer(minLength: 12)

                gradeValueControl(showGrade: showGrade, firstLine: firstLine, secondLine: secondLine)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .sheet(isPresented: $showGradeScratchSheet) {
                GradeScratchView(grade: grade, semester: semester)
            }
            .sheet(isPresented: $showGradeGuessSheet) {
                GradeGuessView(grade: grade, semester: semester)
            }
        }

        private func gradeValueControl(showGrade: Bool, firstLine: String, secondLine: String) -> some View {
            VStack(alignment: .trailing, spacing: 6) {
                Menu {
                    if showGrade {
                        Button {
                            shownGrades.removeAll { $0 == grade.id }
                        } label: {
                            Label("隐藏成绩", systemImage: "eye.slash")
                        }
                    } else {
                        Button {
                            shownGrades.append(grade.id)
                        } label: {
                            Label("显示成绩", systemImage: "eye")
                        }

                        Section(header: Text("小游戏")) {
                            Button {
                                showGradeScratchSheet.toggle()
                            } label: {
                                Label("成绩刮刮乐", systemImage: "ticket")
                            }

//                            Button {
//                                showGradeGuessSheet.toggle()
//                            } label: {
//                                Label("成绩猜一猜", systemImage: "dice")
//                            }
                        }
                    }
                } label: {
                    ZStack {
                        Text(firstLine)
                            .font(.headline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color(UIColor.label))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .opacity(showGrade ? 1 : 0)
                            .offset(y: showGrade ? 0 : 2)

                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.semibold))
                            Text("已隐藏")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                        .opacity(showGrade ? 0 : 1)
                        .offset(y: showGrade ? -2 : 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(showGrade ? Color.mint.opacity(0.18) : Color(UIColor.tertiarySystemFill))
                    )
                    .overlay(
                        Capsule()
                            .stroke(showGrade ? Color.mint.opacity(0.3) : Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                    .animation(.snappy(duration: 0.24, extraBounce: 0), value: showGrade)
                }

                Text(secondLine.isEmpty ? " " : secondLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .opacity(showGrade && !secondLine.isEmpty ? 1 : 0)
                    .animation(.snappy(duration: 0.2, extraBounce: 0), value: showGrade)
            }
        }
    }

    struct MetaPill: View {
        let systemImage: String
        let text: String

        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                Text(text)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(UIColor.tertiarySystemFill))
            )
        }
    }
    
    struct ExamRow: View {
        let exam: ElectSysAPI.Exam

        private enum ExamState {
            case upcoming
            case ongoing
            case ended
            case noDate
        }

        private var state: ExamState {
            if exam.start == nil || exam.end == nil {
                return .noDate
            }

            if exam.start! > .now {
                return .upcoming
            }

            if exam.end! < .now {
                return .ended
            }

            return .ongoing
        }

        private var statusText: String {
            switch state {
            case .upcoming: return "即将开始"
            case .ongoing: return "进行中"
            case .ended: return "已结束"
            case .noDate: return "待安排"
            }
        }

        private var statusColor: Color {
            switch state {
            case .upcoming: return .blue
            case .ongoing: return .orange
            case .ended: return .green
            case .noDate: return .secondary
            }
        }

        private var timeText: String {
            let startDate = exam.start?.formattedRelativeDate() ?? "无日期"
            let startTime = exam.start?.formatted(format: "H:mm") ?? ""
            let endTime = exam.end?.formatted(format: "H:mm") ?? ""
            return "\(startDate) \(startTime)-\(endTime)".trimmingCharacters(in: .whitespaces)
        }

        private var locationText: String {
            "\(exam.campus)\(exam.location)"
        }

        private var statusBadge: some View {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(statusColor.opacity(0.15))
            )
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(exam.courseName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    statusBadge
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(timeText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(locationText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground).opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(statusColor.opacity(0.15), lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }
}

#Preview {
    ExamView()
}
