//
//  Common.swift
//  MySJTU
//
//  Created by boar on 2024/11/25.
//

enum College: Int {
    case sjtu = 1
    case shsmu = 2
    case sjtug = 3
    case joint = 4
}

enum CustomScheduleCategory: String, Codable {
    case custom = "custom"
    case exam = "exam"
}

struct CourseClassSchedule: Codable {
    var course: Course
    var class_: Class
    var schedules: [Schedule]
    var organization: Organization?
    var remarks: [ClassRemark]?
}
