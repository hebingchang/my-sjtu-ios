//
//  Common.swift
//  MySJTU
//
//  Created by boar on 2024/11/25.
//

enum College: Int {
    case custom = 0
    case sjtu = 1
    case shsmu = 2
    case sjtug = 3
}

struct CourseClassSchedule: Codable {
    var course: Course
    var class_: Class
    var schedules: [Schedule]
    var organization: Organization?
    var remarks: [ClassRemark]?
}
