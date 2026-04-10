//
//  AcademicContextService.swift
//  MySJTU
//
//  Created by boar on 2026/04/04.
//

import Foundation
import GRDB

struct AcademicContextSnapshot {
    struct Entry {
        let college: College
        let sourceName: String
        let semester: Semester?
        let displayWeek: Int?
    }

    let colleges: [College]
    let sourceName: String
    let databaseAvailable: Bool
    let entries: [Entry]
}

enum SemesterDateComparison: String, CaseIterable, Codable {
    case earlier
    case equal
    case later

    var displayName: String {
        switch self {
        case .earlier:
            return "早于"
        case .equal:
            return "等于"
        case .later:
            return "晚于"
        }
    }

    static func parse(_ rawValue: String) -> Self? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "早于", "before", "earlier", "previous", "<":
            return .earlier
        case "等于", "equal", "equals", "on", "=":
            return .equal
        case "晚于", "after", "later", "next", ">":
            return .later
        default:
            return nil
        }
    }
}

struct AcademicSemesterLookupSnapshot {
    struct Entry {
        let college: College
        let sourceName: String
        let semester: Semester?
    }

    let sourceName: String
    let comparison: SemesterDateComparison
    let requestedDate: Date
    let databaseAvailable: Bool
    let entries: [Entry]
}

struct AcademicDateScheduleSnapshot {
    struct Item {
        enum Kind: String {
            case course
            case custom

            var displayName: String {
                switch self {
                case .course:
                    return "课程"
                case .custom:
                    return "自定义日程"
                }
            }

            var sortPriority: Int {
                switch self {
                case .course:
                    return 0
                case .custom:
                    return 1
                }
            }
        }

        let kind: Kind
        let college: College?
        let sourceName: String
        let name: String
        let startAt: Date
        let endAt: Date
        let location: String?
        let teachers: [String]
    }

    let sourceName: String
    let requestedDate: Date
    let databaseAvailable: Bool
    let items: [Item]
}

enum AcademicContextService {
    private static let seasonNames = ["秋", "春", "夏"]

    static func selectedColleges(defaults: UserDefaults = .shared) -> [College] {
        let rawCollegeValue = defaults.object(forKey: "collegeId") as? Int ?? College.sjtu.rawValue
        let selectedCollege = College(rawValue: rawCollegeValue) ?? .sjtu
        let showBothCollege = defaults.bool(forKey: "showBothCollege")

        if selectedCollege == .sjtu && showBothCollege {
            return [.sjtu, .sjtug]
        }

        return [selectedCollege]
    }

    static func selectedSourceName(defaults: UserDefaults = .shared) -> String {
        let colleges = selectedColleges(defaults: defaults)
        if colleges == [.sjtu, .sjtug] {
            return "本科 + 研究生"
        }

        return shortName(for: colleges.first ?? .sjtu)
    }

    static func shortName(for college: College) -> String {
        switch college {
        case .sjtu:
            return "本科"
        case .sjtug:
            return "研究生"
        case .joint:
            return "密院 / 浦江"
        case .shsmu:
            return "医学院"
        }
    }

    static func semesterDisplayTitle(for semester: Semester) -> String {
        if let name = semester.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        let seasonName: String
        if seasonNames.indices.contains(semester.semester - 1) {
            seasonName = seasonNames[semester.semester - 1]
        } else {
            seasonName = "未知"
        }

        return "\(semester.year) 学年\(seasonName)季学期"
    }

    static func currentSnapshot(referenceDate: Date = .now, defaults: UserDefaults = .shared) -> AcademicContextSnapshot {
        let colleges = selectedColleges(defaults: defaults)
        let sourceName = selectedSourceName(defaults: defaults)

        guard let pool = Eloquent.pool else {
            return AcademicContextSnapshot(
                colleges: colleges,
                sourceName: sourceName,
                databaseAvailable: false,
                entries: colleges.map {
                    AcademicContextSnapshot.Entry(
                        college: $0,
                        sourceName: shortName(for: $0),
                        semester: nil,
                        displayWeek: nil
                    )
                }
            )
        }

        do {
            let semesterByCollege = try pool.read { db in
                var result: [College: Semester] = [:]
                for college in colleges {
                    result[college] = try Semester
                        .filter(Column("college") == college && Column("start_at") <= referenceDate && Column("end_at") > referenceDate)
                        .fetchOne(db)
                }
                return result
            }

            return AcademicContextSnapshot(
                colleges: colleges,
                sourceName: sourceName,
                databaseAvailable: true,
                entries: colleges.map { college in
                    let semester = semesterByCollege[college]
                    return AcademicContextSnapshot.Entry(
                        college: college,
                        sourceName: shortName(for: college),
                        semester: semester,
                        displayWeek: semester.flatMap { $0.displayWeekIndex(for: referenceDate).map { $0 + 1 } }
                    )
                }
            )
        } catch {
            return AcademicContextSnapshot(
                colleges: colleges,
                sourceName: sourceName,
                databaseAvailable: false,
                entries: colleges.map {
                    AcademicContextSnapshot.Entry(
                        college: $0,
                        sourceName: shortName(for: $0),
                        semester: nil,
                        displayWeek: nil
                    )
                }
            )
        }
    }

    static func semesterLookup(
        comparison: SemesterDateComparison,
        date: Date,
        defaults: UserDefaults = .shared
    ) -> AcademicSemesterLookupSnapshot {
        let colleges = selectedColleges(defaults: defaults)
        let sourceName = selectedSourceName(defaults: defaults)

        guard let pool = Eloquent.pool else {
            return AcademicSemesterLookupSnapshot(
                sourceName: sourceName,
                comparison: comparison,
                requestedDate: date,
                databaseAvailable: false,
                entries: colleges.map {
                    AcademicSemesterLookupSnapshot.Entry(
                        college: $0,
                        sourceName: shortName(for: $0),
                        semester: nil
                    )
                }
            )
        }

        do {
            let semesterByCollege = try pool.read { db in
                var result: [College: Semester] = [:]
                for college in colleges {
                    result[college] = try resolvedSemester(
                        matching: comparison,
                        for: date,
                        college: college,
                        in: db
                    )
                }
                return result
            }

            return AcademicSemesterLookupSnapshot(
                sourceName: sourceName,
                comparison: comparison,
                requestedDate: date,
                databaseAvailable: true,
                entries: colleges.map { college in
                    AcademicSemesterLookupSnapshot.Entry(
                        college: college,
                        sourceName: shortName(for: college),
                        semester: semesterByCollege[college]
                    )
                }
            )
        } catch {
            return AcademicSemesterLookupSnapshot(
                sourceName: sourceName,
                comparison: comparison,
                requestedDate: date,
                databaseAvailable: false,
                entries: colleges.map {
                    AcademicSemesterLookupSnapshot.Entry(
                        college: $0,
                        sourceName: shortName(for: $0),
                        semester: nil
                    )
                }
            )
        }
    }

    static func dateScheduleLookup(
        date: Date,
        defaults: UserDefaults = .shared
    ) -> AcademicDateScheduleSnapshot {
        let normalizedDate = date.startOfDay()
        let colleges = selectedColleges(defaults: defaults)
        let sourceName = selectedSourceName(defaults: defaults)

        guard let pool = Eloquent.pool else {
            return AcademicDateScheduleSnapshot(
                sourceName: sourceName,
                requestedDate: normalizedDate,
                databaseAvailable: false,
                items: []
            )
        }

        do {
            let items = try pool.read { db in
                let courseItems = try colleges.reduce(
                    into: [AcademicDateScheduleSnapshot.Item]()
                ) { partialResult, college in
                    try partialResult.append(
                        contentsOf: courseScheduleItems(for: college, on: normalizedDate, in: db)
                    )
                }
                let customItems = try customScheduleItems(
                    for: colleges,
                    on: normalizedDate,
                    fallbackSourceName: sourceName,
                    in: db
                )
                return (courseItems + customItems).sorted(by: scheduleItemSort)
            }

            return AcademicDateScheduleSnapshot(
                sourceName: sourceName,
                requestedDate: normalizedDate,
                databaseAvailable: true,
                items: items
            )
        } catch {
            return AcademicDateScheduleSnapshot(
                sourceName: sourceName,
                requestedDate: normalizedDate,
                databaseAvailable: false,
                items: []
            )
        }
    }

    private static func resolvedSemester(
        matching comparison: SemesterDateComparison,
        for date: Date,
        college: College,
        in db: Database
    ) throws -> Semester? {
        let containingSemester = try Semester
            .filter(Column("college") == college && Column("start_at") <= date && Column("end_at") > date)
            .order(Column("start_at"))
            .fetchOne(db)

        switch comparison {
        case .equal:
            return containingSemester
        case .earlier:
            if let containingSemester {
                return try Semester
                    .filter(Column("college") == college && Column("start_at") < containingSemester.start_at)
                    .order(Column("start_at").desc)
                    .fetchOne(db)
            }

            return try Semester
                .filter(Column("college") == college && Column("end_at") <= date)
                .order(Column("end_at").desc)
                .fetchOne(db)
        case .later:
            if let containingSemester {
                return try Semester
                    .filter(Column("college") == college && Column("start_at") >= containingSemester.end_at)
                    .order(Column("start_at"))
                    .fetchOne(db)
            }

            return try Semester
                .filter(Column("college") == college && Column("start_at") > date)
                .order(Column("start_at"))
                .fetchOne(db)
        }
    }

    private static func courseScheduleItems(
        for college: College,
        on date: Date,
        in db: Database
    ) throws -> [AcademicDateScheduleSnapshot.Item] {
        let semesters = try Semester
            .filter(Column("college") == college && Column("start_at") <= date && Column("end_at") > date)
            .order(Column("start_at"))
            .fetchAll(db)

        return try semesters.reduce(
            into: [AcademicDateScheduleSnapshot.Item]()
        ) { partialResult, semester in
            guard let week = semester.displayWeekIndex(for: date) else {
                return
            }

            let day = (date.get(.weekday) + 5) % 7
            let request = Schedule
                .including(required: Schedule.class_
                    .including(required: Class.course)
                    .filter(Column("semester_id") == semester.id))
                .filter(
                    Column("week") == week &&
                    Column("is_start") == true &&
                    Column("college") == college &&
                    Column("day") == day
                )

            let scheduleItems = try ScheduleInfo.fetchAll(db, request).map { info in
                AcademicDateScheduleSnapshot.Item(
                    kind: .course,
                    college: college,
                    sourceName: shortName(for: college),
                    name: normalizedText(info.course.name)
                        ?? normalizedText(info.class_.name)
                        ?? "未命名课程",
                    startAt: date.timeOfDay("H:mm", timeStr: info.schedule.startTime()) ?? date,
                    endAt: date.timeOfDay("H:mm", timeStr: info.schedule.finishTime()) ?? date,
                    location: normalizedCourseLocation(info.schedule.classroom),
                    teachers: normalizedTeachers(
                        primary: info.schedule.teachers,
                        fallback: info.class_.teachers
                    )
                )
            }

            partialResult.append(contentsOf: scheduleItems)
        }
    }

    private static func customScheduleItems(
        for colleges: [College],
        on date: Date,
        fallbackSourceName: String,
        in db: Database
    ) throws -> [AcademicDateScheduleSnapshot.Item] {
        let dayStart = date.startOfDay()
        let dayEnd = dayStart.addDays(1)
        let schedules = try CustomSchedule
            .filter(
                colleges.contains(Column("college")) &&
                Column("begin") < dayEnd &&
                Column("end") > dayStart
            )
            .fetchAll(db)

        return schedules.map { schedule in
            AcademicDateScheduleSnapshot.Item(
                kind: .custom,
                college: schedule.college,
                sourceName: schedule.college.map(shortName(for:)) ?? fallbackSourceName,
                name: normalizedText(schedule.name) ?? "未命名日程",
                startAt: max(schedule.begin, dayStart),
                endAt: min(schedule.end, dayEnd),
                location: normalizedText(schedule.location),
                teachers: []
            )
        }
    }

    private static func normalizedCourseLocation(_ classroom: String) -> String? {
        let normalizedClassroom = normalizedText(classroom)
        if normalizedClassroom == "." {
            return "不排教室"
        }
        return normalizedClassroom
    }

    private static func normalizedTeachers(primary: [String]?, fallback: [String]) -> [String] {
        let primaryTeachers = normalizedTexts(primary ?? [])
        if !primaryTeachers.isEmpty {
            return primaryTeachers
        }
        return normalizedTexts(fallback)
    }

    private static func normalizedTexts(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            guard let normalizedValue = normalizedText(value) else {
                return nil
            }
            guard seen.insert(normalizedValue).inserted else {
                return nil
            }
            return normalizedValue
        }
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func scheduleItemSort(
        lhs: AcademicDateScheduleSnapshot.Item,
        rhs: AcademicDateScheduleSnapshot.Item
    ) -> Bool {
        if lhs.startAt != rhs.startAt {
            return lhs.startAt < rhs.startAt
        }

        if lhs.endAt != rhs.endAt {
            return lhs.endAt < rhs.endAt
        }

        if lhs.sourceName != rhs.sourceName {
            return lhs.sourceName.localizedStandardCompare(rhs.sourceName) == .orderedAscending
        }

        if lhs.kind.sortPriority != rhs.kind.sortPriority {
            return lhs.kind.sortPriority < rhs.kind.sortPriority
        }

        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
