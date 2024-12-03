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

struct Schedule: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "schedules"
    static let class_ = belongsTo(Class.self, key: "classes")

    var class_id: String
    var college: College
    var classroom: String
    var day: Int
    var period: Int
    var week: Int
    var is_start: Bool
    var length: Int
}

struct ScheduleInfo: FetchableRecord, Decodable, Equatable, Identifiable {
    static func == (lhs: ScheduleInfo, rhs: ScheduleInfo) -> Bool {
        lhs.class_.id == rhs.class_.id &&
        lhs.course.code == rhs.course.code &&
        lhs.schedule.week == rhs.schedule.week &&
        lhs.schedule.day == rhs.schedule.day &&
        lhs.schedule.period == rhs.schedule.period
    }
    
    var id: String { "\(schedule.class_id),\(schedule.week),\(schedule.day),\(schedule.period)" }
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
