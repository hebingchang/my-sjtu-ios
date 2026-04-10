//
//  Schedule.swift
//  MySJTU
//
//  Created by boar on 2024/11/05.
//

import Foundation
import GRDB

extension College: DatabaseValueConvertible, Codable {
}

struct Semester: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "semesters"

    var id: String
    var college: College
    var year: Int
    var semester: Int
    var start_at: Date
    var end_at: Date
    var name: String?
}

extension Semester {
    private func lastIncludedMoment(using calendar: Calendar = .iso8601) -> Date {
        max(start_at, end_at.addSeconds(-1, using: calendar))
    }

    func contains(_ date: Date) -> Bool {
        start_at <= date && date < end_at
    }

    func overlapsWeek(containing date: Date, using calendar: Calendar = .iso8601) -> Bool {
        let weekStart = date.startOfWeek(using: calendar)
        let weekEnd = weekStart.addWeeks(1, using: calendar)
        return start_at < weekEnd && end_at > weekStart
    }

    func displayWeekReferenceDate(for date: Date, isWeekContext: Bool, using calendar: Calendar = .iso8601) -> Date? {
        if contains(date) {
            return date
        }

        guard isWeekContext, overlapsWeek(containing: date, using: calendar) else {
            return nil
        }

        if date < start_at {
            return start_at
        }

        return lastIncludedMoment(using: calendar)
    }

    func displayWeekIndex(for date: Date, isWeekContext: Bool = false, using calendar: Calendar = .iso8601) -> Int? {
        guard let referenceDate = displayWeekReferenceDate(for: date, isWeekContext: isWeekContext, using: calendar) else {
            return nil
        }

        return referenceDate.weeksSince(start_at, using: calendar)
    }

    func displayWeekCount(using calendar: Calendar = .iso8601) -> Int {
        max(1, lastIncludedMoment(using: calendar).weeksSince(start_at, using: calendar) + 1)
    }

    func displayDayRangeInWeek(containing date: Date, using calendar: Calendar = .iso8601) -> ClosedRange<Int>? {
        let weekStart = date.startOfWeek(using: calendar)
        let weekEnd = weekStart.addWeeks(1, using: calendar)
        let overlapStart = max(start_at.startOfDay(using: calendar), weekStart)
        let overlapEnd = min(end_at, weekEnd)

        guard overlapStart < overlapEnd else {
            return nil
        }

        let overlapLastDay = overlapEnd.addSeconds(-1, using: calendar).startOfDay(using: calendar)
        let startDay = overlapStart.daysSince(weekStart, using: calendar)
        let endDay = overlapLastDay.daysSince(weekStart, using: calendar)
        return startDay...endDay
    }

    func distanceToDisplayWeekReference(for date: Date, isWeekContext: Bool, using calendar: Calendar = .iso8601) -> TimeInterval {
        guard let referenceDate = displayWeekReferenceDate(for: date, isWeekContext: isWeekContext, using: calendar) else {
            return .greatestFiniteMagnitude
        }

        return abs(referenceDate.timeIntervalSince(date))
    }

    func dateForDisplayWeek(_ week: Int, matchingWeekdayOf date: Date, using calendar: Calendar = .iso8601) -> Date {
        let weekStart = start_at.startOfWeek(using: calendar).addWeeks(week - 1, using: calendar)
        let weekdayOffset = date.daysSince(date.startOfWeek(using: calendar), using: calendar)
        return weekStart.addDays(weekdayOffset, using: calendar)
    }
}

struct Organization: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "organizations"

    var id: String
    var college: College
    var name: String
}

struct Course: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "courses"

    var code: String
    var college: College
    var name: String
}

struct Class: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "classes"

    static let semester = belongsTo(Semester.self)
    static let course = belongsTo(Course.self, key: "courses")
    static let organization = belongsTo(Organization.self, key: "organizations")

    var id: String
    var college: College
    var color: String
    var course_code: String
    var organization_id: String?
    var name: String
    var code: String
    var teachers: [String]
    var hours: Float
    var credits: Float
    var semester_id: String
}

struct ClassRemark: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "class_remarks"
    
    static let class_ = belongsTo(Class.self, key: "classes")
    
    var class_id: String
    var college: College
    var remark: String
}

struct CanvasClass: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "canvas_lms"
    
    static let class_ = belongsTo(Class.self, key: "classes")
    
    var id: String
    var college: College
    var class_id: String
}

struct CustomSchedule: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "custom_schedules"
    
    var id: Int64?
    var name: String
    var description: String
    var location: String
    var begin: Date
    var end: Date
    var semester_id: String?
    var week: Int?
    var category: CustomScheduleCategory
    var college: College?
    var color: String?
}

extension CustomSchedule {
    func y() -> CGFloat {
        guard let college else { return 0 }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current

        let (startHour, endHour) = CollegeTimeTable[college]!.getHours()
        let timeTableStartTime = formatter.date(from: "\(startHour):00")!
        let timeTableEndTime = formatter.date(from: "\(endHour):00")!
        let startTime = formatter.date(from: formatter.string(from: begin))!

        return startTime.timeIntervalSince(timeTableStartTime) / timeTableEndTime.timeIntervalSince(timeTableStartTime) + height() / 2
    }

    func height() -> CGFloat {
        guard let college else { return 0 }

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone.current

        let (startHour, endHour) = CollegeTimeTable[college]!.getHours()
        let timeTableStartTime = formatter.date(from: "\(startHour):00")!
        let timeTableEndTime = formatter.date(from: "\(endHour):00")!
        let startTime = formatter.date(from: formatter.string(from: begin))!
        let finishTime = formatter.date(from: formatter.string(from: end))!

        return finishTime.timeIntervalSince(startTime) / timeTableEndTime.timeIntervalSince(timeTableStartTime)
    }

    func duration() -> TimeInterval {
        return end.timeIntervalSince(begin)
    }
    
    private func isBefore(time1: String, time2: String) -> Bool {
        let selfHour = Int(time1.split(separator: ":").first!)!
        let otherHour = Int(time2.split(separator: ":").first!)!
        if selfHour != otherHour {
            return selfHour < otherHour
        }
        let selfMinute = Int(time1.split(separator: ":").last!)!
        let otherMinute = Int(time2.split(separator: ":").last!)!
        return selfMinute < otherMinute
    }

    private func overlapsDisplayedTimeSlot(_ period: Period, scheduleStartTime: String, scheduleEndTime: String) -> Bool {
        isBefore(time1: scheduleStartTime, time2: period.finish) &&
        isBefore(time1: period.start, time2: scheduleEndTime)
    }

    func period() -> Int {
        guard let college else { return 0 }
        let periods = CollegeTimeTable[college]!
        let scheduleStartTime = begin.formatted(format: "H:mm")
        let scheduleEndTime = end.formatted(format: "H:mm")

        return periods.firstIndex { period in
            overlapsDisplayedTimeSlot(
                period,
                scheduleStartTime: scheduleStartTime,
                scheduleEndTime: scheduleEndTime
            )
        } ?? 0
    }
    
    func length() -> Int {
        guard let college else { return 0 }
        let scheduleStartTime = begin.formatted(format: "H:mm")
        let scheduleEndTime = end.formatted(format: "H:mm")
        let periods = CollegeTimeTable[college]!
        return periods.reduce(into: 0) { count, period in
            if overlapsDisplayedTimeSlot(
                period,
                scheduleStartTime: scheduleStartTime,
                scheduleEndTime: scheduleEndTime
            ) {
                count += 1
            }
        }
    }
}

class CustomScheduleEntry: ObservableObject {
    @Published var id: Int64?
    @Published var name: String = ""
    @Published var description: String = ""
    @Published var location: String = ""
    @Published var begin: Date = .now.startOfHour()
    @Published var end: Date = .now.startOfHour().addHours(1)
    @Published var college: College?
    @Published var color: String = "#5D737E"
    
    init() {}
    init(schedule: CustomSchedule) {
        id = schedule.id
        name = schedule.name
        description = schedule.description
        location = schedule.location
        begin = schedule.begin
        end = schedule.end
        college = schedule.college
        color = schedule.color ?? "#5D737E"
    }
    init(college: College) {
        self.college = college
    }
}

struct Schedule: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "schedules"
    static let class_ = belongsTo(Class.self, key: "classes")

    var class_id: String
    var college: College
    var classroom: String
    var day: Int
    var period: Int // period_id
    var week: Int
    var is_start: Bool
    var length: Int
    var teachers: [String]?
    var remark: String?
}

struct ScheduleInfo: FetchableRecord, Decodable, Equatable, Identifiable {
    static func == (lhs: ScheduleInfo, rhs: ScheduleInfo) -> Bool {
        lhs.class_.id == rhs.class_.id &&
        lhs.course.code == rhs.course.code &&
        lhs.schedule.week == rhs.schedule.week &&
        lhs.schedule.day == rhs.schedule.day &&
        lhs.schedule.period == rhs.schedule.period
    }
    
    var id: String { "\(class_.college),\(schedule.class_id),\(schedule.week),\(schedule.day),\(schedule.period)" }
    var schedule: Schedule
    var class_: Class
    var course: Course

    enum CodingKeys: String, CodingKey {
        case schedule = "schedules"
        case class_ = "classes"
        case course = "courses"
    }
}

extension Schedule {
    func start() -> Period {
        CollegeTimeTable[college]!.first { p in
            p.id == period
        }!
    }

    func finish() -> Period {
        CollegeTimeTable[college]!.first { p in
            p.id == period + length - 1
        }!
    }
    
    func periodIndex() -> Int {
        CollegeTimeTable[college]!.firstIndex { p in
            p.id == period
        }!
    }

    func startTime() -> String {
        start().start
    }

    func finishTime() -> String {
        finish().finish
    }

    func y() -> CGFloat {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let start = start().start
        let (startHour, endHour) = CollegeTimeTable[college]!.getHours()
        let timeTableStartTime = formatter.date(from: "\(startHour):00")!
        let timeTableEndTime = formatter.date(from: "\(endHour):00")!
        let startTime = formatter.date(from: start)!

        return startTime.timeIntervalSince(timeTableStartTime) / timeTableEndTime.timeIntervalSince(timeTableStartTime) + height() / 2
    }

    func height() -> CGFloat {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let start = start().start
        let finish = finish().finish
        let (startHour, endHour) = CollegeTimeTable[college]!.getHours()
        let timeTableStartTime = formatter.date(from: "\(startHour):00")!
        let timeTableEndTime = formatter.date(from: "\(endHour):00")!
        let startTime = formatter.date(from: start)!
        let finishTime = formatter.date(from: finish)!

        return finishTime.timeIntervalSince(startTime) / timeTableEndTime.timeIntervalSince(timeTableStartTime)
    }

    func duration() -> TimeInterval {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = start().start
        let end = finish().finish


        guard let start = formatter.date(from: start),
              let end = formatter.date(from: end)
        else {
            return 0
        }

        return end.timeIntervalSince(start)
    }
}
