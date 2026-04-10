//
//  ExamAndGradeToolSupport.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

enum ExamAndGradeSemesterSelection: String, CaseIterable, Sendable {
    case autumn = "秋"
    case spring = "春"
    case summer = "夏"

    var code: Int {
        switch self {
        case .autumn:
            return 1
        case .spring:
            return 2
        case .summer:
            return 3
        }
    }

    var displayName: String {
        rawValue
    }

    static func parse(_ rawValue: String) -> Self? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "秋", "秋季", "秋季学期", "autumn", "fall":
            return .autumn
        case "春", "春季", "春季学期", "spring":
            return .spring
        case "夏", "夏季", "夏季学期", "summer":
            return .summer
        default:
            return nil
        }
    }
}

private enum ExamToolItemStatus: String {
    case ongoing
    case upcoming
    case ended
    case unscheduled

    var displayName: String {
        switch self {
        case .ongoing:
            return "进行中"
        case .upcoming:
            return "即将开始"
        case .ended:
            return "已结束"
        case .unscheduled:
            return "未设置时间"
        }
    }

    var sortPriority: Int {
        switch self {
        case .ongoing:
            return 0
        case .upcoming:
            return 1
        case .ended:
            return 2
        case .unscheduled:
            return 3
        }
    }
}

extension AIService {
    static func enabledExamAndGradeAccount(
        userDefaults: UserDefaults = .standard
    ) -> WebAuthAccount? {
        storedAccounts(userDefaults: userDefaults).first {
            $0.provider == .jaccount && $0.enabledFeatures.contains(.examAndGrade)
        }
    }

    static func examAndGradeUnavailableErrorText() -> String {
        "当前 jAccount 尚未启用考试与成绩功能，请先在账户页中启用考试与成绩功能。"
    }

    static func examAndGradeToolErrorText(
        _ error: Error,
        subject: String
    ) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .sessionExpired:
                return "jAccount 会话可能已过期，请在账户页中重新登录后再试。"
            case .noAccount:
                return "当前未找到可用的 jAccount 账户，请先登录并启用考试与成绩功能。"
            case .remoteError(let message), .runtimeError(let message):
                return message
            case .internalError:
                return "无法获取\(subject)，请稍后重试。"
            }
        }

        return "无法获取\(subject)，请稍后重试。"
    }

    static func examAndGradeSemesterDisplayName(
        year: Int,
        semester: ExamAndGradeSemesterSelection
    ) -> String {
        "\(year) 学年\(semester.displayName)季学期"
    }

    static func examAndGradeStatisticsRangeDescription(
        startYear: Int?,
        startSemester: ExamAndGradeSemesterSelection?,
        endYear: Int?,
        endSemester: ExamAndGradeSemesterSelection?
    ) -> String {
        guard startYear != nil || startSemester != nil || endYear != nil || endSemester != nil else {
            return "全部学期"
        }

        let startName: String?
        if let startYear, let startSemester {
            startName = examAndGradeSemesterDisplayName(year: startYear, semester: startSemester)
        } else {
            startName = nil
        }

        let endName: String?
        if let endYear, let endSemester {
            endName = examAndGradeSemesterDisplayName(year: endYear, semester: endSemester)
        } else {
            endName = nil
        }

        if let startName, let endName {
            if startYear == endYear && startSemester == endSemester {
                return startName
            }

            return "\(startName)至\(endName)"
        }

        if let startName {
            return "从\(startName)起的全部学期"
        }

        if let endName {
            return "截至\(endName)的全部学期"
        }

        return "全部学期"
    }

    static func fetchSemesterExamArrangementsResult(
        account: WebAuthAccount,
        year: Int,
        semester: ExamAndGradeSemesterSelection
    ) async throws -> SemesterExamArrangementsToolResult {
        let api = ElectSysAPI(cookies: account.cookies.compactMap(\.httpCookie))
        try await api.openIdConnect()

        let exams = try await api.getExams(year: year, semester: semester.code)
        let sortedExams = exams.sorted(by: sortSemesterExamItems)

        let ongoingCount = exams.filter { examToolItemStatus(for: $0) == .ongoing }.count
        let upcomingCount = exams.filter { examToolItemStatus(for: $0) == .upcoming }.count
        let endedCount = exams.filter { examToolItemStatus(for: $0) == .ended }.count
        let unscheduledCount = exams.filter { examToolItemStatus(for: $0) == .unscheduled }.count

        return SemesterExamArrangementsToolResult(
            year: year,
            semester: semester.displayName,
            semesterName: examAndGradeSemesterDisplayName(year: year, semester: semester),
            examCount: exams.count,
            ongoingCount: ongoingCount,
            upcomingCount: upcomingCount,
            endedCount: endedCount,
            unscheduledCount: unscheduledCount,
            items: sortedExams.map { exam in
                let status = examToolItemStatus(for: exam)
                return SemesterExamArrangementsToolResult.Item(
                    code: exam.code,
                    courseName: exam.courseName,
                    courseCode: exam.courseCode,
                    classCode: exam.classCode,
                    examName: exam.examName,
                    examType: normalizedNonEmptyText(exam.type),
                    gradeType: normalizedNonEmptyText(exam.gradeType),
                    campus: exam.campus,
                    location: exam.location,
                    startAt: exam.start?.formatted(format: "yyyy-MM-dd HH:mm"),
                    endAt: exam.end?.formatted(format: "yyyy-MM-dd HH:mm"),
                    status: status.rawValue,
                    statusText: status.displayName,
                    isRebuild: exam.isRebuild,
                    order: exam.order
                )
            }
        )
    }

    static func fetchSemesterGradesResult(
        account: WebAuthAccount,
        year: Int,
        semester: ExamAndGradeSemesterSelection
    ) async throws -> SemesterGradesToolResult {
        let api = ElectSysAPI(cookies: account.cookies.compactMap(\.httpCookie))
        try await api.openIdConnect()

        let grades = try await api.getGrades(year: year, semester: semester.code)

        return SemesterGradesToolResult(
            year: year,
            semester: semester.displayName,
            semesterName: examAndGradeSemesterDisplayName(year: year, semester: semester),
            gradeCount: grades.count,
            items: grades.map { grade in
                let normalizedGrade = normalizedNonEmptyText(grade.grade)
                let normalizedRemark = normalizedNonEmptyText(grade.remark)
                let displayValue = normalizedGrade ?? normalizedRemark ?? grade.score
                let secondaryValue = (normalizedGrade == nil && normalizedRemark == nil) ? nil : grade.score

                return SemesterGradesToolResult.Item(
                    id: grade.id,
                    courseName: grade.courseName,
                    courseCode: grade.courseCode,
                    credit: grade.credit,
                    score: grade.score,
                    grade: normalizedGrade,
                    remark: normalizedRemark,
                    teacher: grade.teacher,
                    displayValue: displayValue,
                    secondaryValue: secondaryValue
                )
            }
        )
    }

    static func fetchGPAStatisticsResult(
        account: WebAuthAccount,
        startYear: Int?,
        startSemester: ExamAndGradeSemesterSelection?,
        endYear: Int?,
        endSemester: ExamAndGradeSemesterSelection?
    ) async throws -> GPAStatisticsToolResult {
        let api = ElectSysAPI(cookies: account.cookies.compactMap(\.httpCookie))
        try await api.openIdConnect()

        let statistics = try await api.getGPAStatistics(
            startYear: startYear,
            startSemester: startSemester?.code,
            endYear: endYear,
            endSemester: endSemester?.code
        )

        let rangeDescription = examAndGradeStatisticsRangeDescription(
            startYear: startYear,
            startSemester: startSemester,
            endYear: endYear,
            endSemester: endSemester
        )

        guard let statistics else {
            return GPAStatisticsToolResult(
                rangeDescription: rangeDescription,
                startYear: startYear,
                startSemester: startSemester?.displayName,
                endYear: endYear,
                endSemester: endSemester?.displayName,
                found: false,
                item: nil
            )
        }

        let gpaRanking = parsedRanking(statistics.gpaRank)
        let academicPointsRanking = parsedRanking(statistics.academicPointsRank)

        return GPAStatisticsToolResult(
            rangeDescription: rangeDescription,
            startYear: startYear,
            startSemester: startSemester?.displayName,
            endYear: endYear,
            endSemester: endSemester?.displayName,
            found: true,
            item: .init(
                className: statistics.className,
                failedCourseCount: Int(statistics.failedCourseCount),
                failedCredits: statistics.failedCredits,
                gpa: statistics.gpa,
                gpaRank: statistics.gpaRank,
                gpaRankPosition: gpaRanking.position,
                totalStudents: gpaRanking.total,
                earnedCredits: statistics.earnedCredits,
                academicPoints: statistics.academicPoints,
                academicPointsRank: statistics.academicPointsRank,
                academicPointsRankPosition: academicPointsRanking.position,
                totalCredits: statistics.totalCredits,
                courseScope: normalizedNonEmptyText(statistics.courseScope),
                collegeName: normalizedNonEmptyText(statistics.collegeName),
                majorName: normalizedNonEmptyText(statistics.majorName),
                updatedAt: normalizedNonEmptyText(statistics.updatedAt)
            )
        )
    }

    private static func examToolItemStatus(
        for exam: ElectSysAPI.Exam,
        now: Date = .now
    ) -> ExamToolItemStatus {
        guard let start = exam.start, let end = exam.end else {
            return .unscheduled
        }

        if start <= now && end >= now {
            return .ongoing
        }

        if start > now {
            return .upcoming
        }

        return .ended
    }

    private static func sortSemesterExamItems(
        _ lhs: ElectSysAPI.Exam,
        _ rhs: ElectSysAPI.Exam
    ) -> Bool {
        let lhsStatus = examToolItemStatus(for: lhs)
        let rhsStatus = examToolItemStatus(for: rhs)

        if lhsStatus.sortPriority != rhsStatus.sortPriority {
            return lhsStatus.sortPriority < rhsStatus.sortPriority
        }

        switch lhsStatus {
        case .ongoing, .upcoming:
            if let lhsStart = lhs.start, let rhsStart = rhs.start, lhsStart != rhsStart {
                return lhsStart < rhsStart
            }
        case .ended:
            if let lhsEnd = lhs.end, let rhsEnd = rhs.end, lhsEnd != rhsEnd {
                return lhsEnd > rhsEnd
            }
        case .unscheduled:
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
        }

        let courseComparison = lhs.courseName.localizedStandardCompare(rhs.courseName)
        if courseComparison != .orderedSame {
            return courseComparison == .orderedAscending
        }

        return lhs.code.localizedStandardCompare(rhs.code) == .orderedAscending
    }

    private static func normalizedNonEmptyText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static func parsedRanking(_ rawValue: String) -> (position: Int?, total: Int?) {
        let components = rawValue
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if components.count == 2 {
            return (Int(components[0]), Int(components[1]))
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return (Int(trimmed), nil)
    }
}
