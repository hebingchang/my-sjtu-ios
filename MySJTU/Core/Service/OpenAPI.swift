//
//  OpenAPI.swift
//  MySJTU
//
//  Created by boar on 2024/11/14.
//

import Foundation
import Alamofire
import SwiftSoup
import Apollo

enum APIError: Error, Equatable {
    case runtimeError(String)
    case remoteError(String)
    case sessionExpired
    case noAccount
    case internalError
}

private struct semester: Codable {
    let id: String
    let year, semester: Int
    let start_date, end_date: String
    let name: String?
}

private struct semesterResponse: Codable {
    let updated_at: Double
    let semesters: [semester]
}

func getSemesters(college: College) async throws -> [Semester] {
    let url = switch college {
    case .joint: "https://s3.jcloud.sjtu.edu.cn/9fd44bb76f604e8597acfcceada7cb83-tongqu/class_table/calendar_joint.json"
    case .shsmu: "https://s3.jcloud.sjtu.edu.cn/9fd44bb76f604e8597acfcceada7cb83-tongqu/class_table/calendar_shsmu.json"
    default: "https://s3.jcloud.sjtu.edu.cn/9fd44bb76f604e8597acfcceada7cb83-tongqu/class_table/calendar.json"
    }

    let response = try await AppAF.session.request(
        url,
        parameters: [
            "r": Date.now.timeIntervalSince1970
        ],
        encoding: URLEncoding(destination: .queryString)
    ).serializingDecodable(semesterResponse.self).value

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    return response.semesters.map {
        Semester(id: $0.id, college: college, year: $0.year, semester: $0.semester, start_at: Date.fromFormat("yyyy-MM-dd", dateStr: $0.start_date)!.startOfDay(), end_at: Date.fromFormat("yyyy-MM-dd", dateStr: $0.end_date)!.startOfDay().addDays(1).startOfDay(),
                 name: $0.name)
    }
}

struct SHSMUOpenAPI {
    var cookies: [HTTPCookie]
    var baseUrl = "https://webvpn2.shsmu.edu.cn/https/77726476706e69737468656265737421fae05288327e7b586d059ce29d51367b9aac"
    
    private struct Response<T: Codable>: Codable {
        let title: String?
        let list: [T]

        enum CodingKeys: String, CodingKey {
            case title = "Title"
            case list = "List"
        }
    }
    
    struct SHSMUBizStruct {
        let MCSID: String
        let CSID: Int?
        let CurriculumID: Int
        let XXKMID: Int?
        let CurriculumType: String
    }

    private struct SHSMUSchedule: Codable {
        let curriculum: String
        let courseCode: String?
        let courseCount: Int
        let classroomAcademy, start: String
        let curriculumType: String
        let mcsid: String?
        let csid: Int?
        let curriculumID: Int?
        let xxkmid: Int?

        enum CodingKeys: String, CodingKey {
            case curriculum = "Curriculum"
            case courseCode = "CourseCode"
            case courseCount = "CourseCount"
            case classroomAcademy = "ClassroomAcademy"
            case start = "Start"
            case curriculumType = "CurriculumType"
            case mcsid = "MCSID"
            case csid = "CSID"
            case curriculumID = "CurriculumID"
            case xxkmid = "XXKMID"
        }
    }
    
    struct SHSMUCourse: Codable {
        let className, courseName, classCode: String
        let content: String?
        let id, teachingCalendarID: Int
        let curriculumScheduleIDs: String
        let classTime: String
        let curriculumType: Int
        let classHour: Double
        let teacher, teacherAccount, college, collegeCode: String
        let workNumber, title: String
        let curriculumName, kcIndex, courseText, welcomeClassroomName: String
        let department: String
        let schoolYear: String
        let semester, classGrade: Int

        enum CodingKeys: String, CodingKey {
            case className = "ClassName"
            case courseName = "CourseName"
            case classCode = "ClassCode"
            case content = "Content"
            case id = "ID"
            case teachingCalendarID = "TeachingCalendarID"
            case curriculumScheduleIDs = "CurriculumScheduleIDs"
            case classTime = "ClassTime"
            case classHour = "ClassHour"
            case curriculumType = "CurriculumType"
            case teacher = "Teacher"
            case teacherAccount = "TeacherAccount"
            case college = "College"
            case collegeCode = "CollegeCode"
            case workNumber = "WorkNumber"
            case title = "Title"
            case curriculumName = "CurriculumName"
            case kcIndex = "KCIndex"
            case courseText = "CourseText"
            case welcomeClassroomName = "Classroom_Name"
            case department = "Department"
            case schoolYear = "SchoolYear"
            case semester = "Semester"
            case classGrade = "ClassGrade"
        }
    }
    
    func getSchedules(semester: Semester, onProgress: (_ fraction: Double) -> Void) async throws -> [CourseClassSchedule] {
        let start = semester.start_at.formattedDate()
        let end = semester.end_at.formattedDate()
        let calendarTableURL = "\(baseUrl)/Home/GetCalendarTable"
        
        func shouldRetryCalendarRequest(_ error: Error) -> Bool {
            if let afError = error as? AFError {
                switch afError {
                case .sessionTaskFailed(let underlyingError):
                    return shouldRetryCalendarRequest(underlyingError)
                case .responseValidationFailed(let reason):
                    if case .unacceptableStatusCode(let statusCode) = reason {
                        return statusCode == 429 || (500...599).contains(statusCode)
                    }
                    return false
                default:
                    return false
                }
            }
            
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                     .networkConnectionLost, .notConnectedToInternet, .cannotLoadFromNetwork:
                    return true
                default:
                    return false
                }
            }
            
            return false
        }
        
        func getCalendarTableWithRetry(
            parameters: [String: String],
            maxRetryCount: Int = 2
        ) async throws -> [SHSMUCourse] {
            var attempt = 0
            var retryDelayInNanoseconds: UInt64 = 300_000_000
            
            while true {
                do {
                    return try await AppAF.session.request(
                        calendarTableURL,
                        parameters: parameters,
                        encoding: URLEncoding(destination: .queryString)
                    ).serializingDecodable([SHSMUCourse].self).value.sorted { $0.kcIndex < $1.kcIndex }
                } catch {
                    if error is CancellationError {
                        throw error
                    }
                    
                    guard attempt < maxRetryCount, shouldRetryCalendarRequest(error) else {
                        throw error
                    }
                    
                    attempt += 1
                    try await Task.sleep(nanoseconds: retryDelayInNanoseconds)
                    retryDelayInNanoseconds *= 2
                }
            }
        }
        
        struct ScheduleTaskResult {
            let listIndex: Int
            let classID: String
            let schedules: [Schedule]
        }
                
        cookies.forEach { cookie in
            AppAF.cookieStorage.setCookie(cookie)
        }
        
        _ = try await AppAF.session.request(
            "\(baseUrl)/Home/Timetable"
        ).serializingString().value
        
        let response = try await AppAF.session.request(
            "\(baseUrl)/Home/GetCurriculumTable",
            parameters: [
                "Start": start,
                "End": end
            ],
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable(Response<SHSMUSchedule>.self).value
        
        var classes: [CourseClassSchedule] = []
        let colors = ClassColors.randomColors()
        
        // initiate classes
        for schedule in response.list {
            if let courseCode = schedule.courseCode,
               schedule.mcsid != nil,
               let curriculumID = schedule.curriculumID {
                var classIndex = classes.firstIndex(where: { $0.class_.id == String(curriculumID) })
                if classIndex == nil {
                    classes.append((
                        CourseClassSchedule(
                            course: Course(code: courseCode.trimSpace(), college: .shsmu, name: schedule.curriculum.trimSpace()),
                            class_: Class(
                                id: String(curriculumID),
                                college: .shsmu,
                                color: colors[classes.count],
                                course_code: courseCode.trimSpace(),
                                name: schedule.curriculum.trimSpace(),
                                code: courseCode.trimSpace(),
                                teachers: [],
                                hours: -1,
                                credits: -1,
                                semester_id: semester.id
                            ),
                            schedules: []
                        )
                    ))
                    classIndex = classes.count - 1
                }
            } else if schedule.curriculumType == "考试" {
                // TODO: exam schedule
            }
        }
        
        let classIndexByID = Dictionary(uniqueKeysWithValues: classes.enumerated().map { item in
            (item.element.class_.id, item.offset)
        })
        
        let maxConcurrentRequests = 6
        var progress = 0
        var scheduleTaskResults = Array<ScheduleTaskResult?>(repeating: nil, count: response.list.count)
        // initiate schedules
        if response.list.isEmpty {
            onProgress(1)
            return classes
        }
        
        for batchStart in stride(from: 0, to: response.list.count, by: maxConcurrentRequests) {
            let batchEnd = min(batchStart + maxConcurrentRequests, response.list.count)
            
            try await withThrowingTaskGroup(of: ScheduleTaskResult?.self) { group in
                for listIndex in batchStart..<batchEnd {
                    let schedule = response.list[listIndex]
                    
                    group.addTask {
                        guard let mcsid = schedule.mcsid,
                              let curriculumID = schedule.curriculumID else {
                            return nil
                        }
                        
                        let classID = String(curriculumID)
                        guard classIndexByID[classID] != nil else {
                            return nil
                        }
                        
                        let startParts = schedule.start.split(separator: "T")
                        guard startParts.count > 1,
                              let startPeriod = getPeriodByTime(college: .shsmu, time: String(startParts[1])),
                              let start = Date.fromFormat("yyyy-MM-dd'T'HH:mm:ss", dateStr: schedule.start, calendar: .iso8601) else {
                            return nil
                        }
                        
                        let response = try await getCalendarTableWithRetry(
                            parameters: [
                                "MCSID": mcsid,
                                "CSID": schedule.csid.map(String.init) ?? "null",
                                "CurriculumID": classID,
                                "XXKMID": schedule.xxkmid.map(String.init) ?? "null",
                                "CurriculumType": schedule.curriculumType
                            ]
                        )
                        
                        var schedules: [Schedule] = []
                        if schedule.courseCount > 0 {
                            schedules.reserveCapacity(schedule.courseCount)
                        }
                        
                        for i in 0..<schedule.courseCount {
                            var dbSchedule = Schedule(
                                class_id: classID,
                                college: .shsmu,
                                classroom: schedule.classroomAcademy.trimSpace(),
                                day: (start.get(.weekday) + 5) % 7,
                                // period: (startPeriod.id >= 5 ? startPeriod.id + 1 : startPeriod.id) + i,
                                period: startPeriod.id + i,
                                week: start.weeksSince(semester.start_at),
                                is_start: i == 0,
                                length: i == 0 ? schedule.courseCount : 0
                            )
                            
                            if i == 0 {
                                dbSchedule.teachers = Array(Set(response.map { part in
                                    part.teacher
                                }))
                                dbSchedule.remark = response.map { part in
                                    "\(part.courseText)：\(part.content ?? "未知内容") (\(part.teacher))"
                                }.joined(separator: "\n")
                            }
                            
                            schedules.append(dbSchedule)
                        }
                        
                        return ScheduleTaskResult(listIndex: listIndex, classID: classID, schedules: schedules)
                    }
                }
                
                for try await result in group {
                    if let result {
                        scheduleTaskResults[result.listIndex] = result
                    }
                    
                    progress += 1
                    onProgress(Double(progress) / Double(response.list.count))
                }
            }
        }
        
        for result in scheduleTaskResults.compactMap({ $0 }) {
            guard let classIndex = classIndexByID[result.classID] else {
                continue
            }
            
            classes[classIndex].schedules.append(contentsOf: result.schedules)
        }

        return classes
    }
    
    func getCourseInfo(schedule: ([[String: String]], CourseClassSchedule)) async throws -> CourseClassSchedule {
        cookies.forEach { cookie in
            AppAF.cookieStorage.setCookie(cookie)
        }
        
        for parameter in schedule.0 {
            let response = try await AppAF.session.request(
                "\(baseUrl)/Home/GetCalendarTable",
                parameters: parameter,
                encoding: URLEncoding(destination: .queryString)
            ).serializingDecodable([SHSMUCourse].self).value
            
            if response.count == 0 {
                continue
            }
            
            var newSchedule = schedule.1
            let org = Set(response.map {
                $0.college.trimSpace()
            }).joined(separator: "，")
            newSchedule.organization = Organization(id: org, college: .shsmu, name: org)
            newSchedule.class_.organization_id = org
            newSchedule.class_.teachers = Array(Set(response.map {
                $0.teacher.trimSpace()
            }))
            newSchedule.class_.name = response.first!.curriculumName.trimSpace()

            return newSchedule
        }
        
        throw APIError.runtimeError("无法获取课程信息")
    }
}

struct SJTUGOpenAPI {
    var cookies: [HTTPCookie]
    
    private struct GraduateResponse: Codable {
        let datas: ScheduleResponse
        let code: String
    }

    private struct ScheduleResponse: Codable {
        let xspkjgcx: Pagination
    }

    private struct Pagination: Codable {
        let rows: [Row]
    }

    // MARK: - Row
    private struct Row: Codable {
        let jasmc: String?
        let xq: Int
        let kcmc: String
        let jsxm: String
        let kbbz: String?
        let bjdm: String
        let bjmc: String
        let jsjcdm: Int
        let kcdm: String
        let zcbh: String

        enum CodingKeys: String, CodingKey {
            case jasmc = "JASMC"
            case xq = "XQ"
            case kcmc = "KCMC"
            case jsxm = "JSXM"
            case kbbz = "KBBZ"
            case bjdm = "BJDM"
            case bjmc = "BJMC"
            case jsjcdm = "JSJCDM"
            case kcdm = "KCDM"
            case zcbh = "ZCBH"
        }
    }
    
    func getSchedules(semester: Semester) async throws -> [CourseClassSchedule] {
        cookies.forEach { cookie in
            AppAF.cookieStorage.setCookie(cookie)
        }
        
        let _ = try await AppAF.session.request("https://yjs.sjtu.edu.cn/gsapp/sys/wdkbapp/*default/index.do")
            .serializingString()
            .value
        
        var semesterString: String {
            var year: Int
            var term: String
            if semester.semester == 1 {
                year = semester.year
            } else {
                year = semester.year + 1
            }
            switch semester.semester {
            case 1:
                term = "09"
            case 2:
                term = "02"
            case 3:
                term = "06"
            default:
                term = ""
            }
            return "\(year)\(term)"
        }
        
        let schedules = try await AppAF.session.request(
            "https://yjs.sjtu.edu.cn/gsapp/sys/wdkbapp/modules/xskcb/xspkjgcx.do",
            method: .post,
            parameters: [
                "XNXQDM": semesterString
            ],
            encoding: URLEncoding.httpBody
        )
            .serializingDecodable(GraduateResponse.self)
            .value
            .datas
            .xspkjgcx
            .rows
        
        let colors = ClassColors.randomColors(n: Set(schedules.map({ schedule in
            schedule.bjmc
        })).count)
        
        return Dictionary(grouping: schedules, by: { $0.bjmc }).values.enumerated().map { (index, entity) in
            var isStartFlags: [Int: Bool] = [:]
            let course = Course(code: entity.first!.kcdm, college: .sjtug, name: entity.first!.kcmc)
            let class_ = Class(id: entity.first!.bjdm, college: .sjtug, color: colors[index], course_code: entity.first!.kcdm, name: entity.first!.bjmc, code: entity.first!.bjmc, teachers: entity.first!.jsxm.components(separatedBy: ","), hours: -1, credits: -1, semester_id: semester.id)
            var daySchedules: [Schedule] = []
            var remarks: [ClassRemark] = []
            
            for schedule in entity {
                for week in schedule.zcbh.indicesOf(string: "1") {
                    var classroom = "未排教室"
                    if let room = schedule.jasmc {
                        classroom = room
                    }
                    
                    daySchedules.append(
                        Schedule(
                            class_id: schedule.bjdm,
                            college: .sjtug,
                            classroom: classroom,
                            day: schedule.xq - 1,
                            period: schedule.jsjcdm - 1,
                            week: week,
                            is_start: true,
                            length: 0
                        )
                    )
                    
                    if let remark = schedule.kbbz, remarks.firstIndex(where: { remark in
                        remark.class_id == schedule.bjdm
                    }) == nil {
                        remarks.append(ClassRemark(class_id: schedule.bjdm, college: .sjtug, remark: remark))
                    }
                }
            }

            return CourseClassSchedule(
                course: course,
                class_: class_,
                schedules: daySchedules.sorted {
                    if $0.week != $1.week {
                        return $0.week < $1.week
                    }

                    if $0.day != $1.day {
                        return $0.day < $1.day
                    }

                    return $0.period < $1.period
                }.enumerated().map { (index, schedule) in
                    var retSchedule = schedule
                    
                    if isStartFlags[index] == nil {
                        retSchedule.is_start = true
                        var diff: Int = 1
                        while daySchedules.first(where: { class_ in
                            class_.week == schedule.week &&
                            class_.day == schedule.day &&
                            class_.classroom == schedule.classroom &&
                            class_.period == schedule.period + diff
                        }) != nil {
                            isStartFlags[index + diff] = false
                            diff += 1
                        }
                        retSchedule.length = diff
                    } else {
                        retSchedule.is_start = false
                    }
                    
                    return retSchedule
                },
                remarks: remarks
            )
        }
    }
}

struct JointOpenAPI {
    var cookies: [HTTPCookie]
    var tokens: [TokenForScopes]

    private static let userInfoURL = "https://coursesel.umji.sjtu.edu.cn/sys/globalInfoByVersion_Login.action"
    private static let termsURL = "https://coursesel.umji.sjtu.edu.cn/smd/findAllByCombo_Term.action"
    private static let lessonTasksURL = "https://coursesel.umji.sjtu.edu.cn/tpm/findStudentLessonTask_LessonTask.action"
    private static let schedulesURL = "https://coursesel.umji.sjtu.edu.cn/tpm/findWeekCalendar_LessonCalendar.action"

    struct UserInfoResponse: Codable {
        let session: Session
        let version: Version
    }

    private struct UserInfoRequest: Codable {
        let version: Version
    }

    private struct TermResponse: Codable {
        let success: Bool
        let data: [Term]?
        let errDesc: String
    }

    private struct LessonCalendarRequest: Codable {
        let termId: String
        let studentId: String
    }

    private struct LessonTaskLookupRequest: Codable {
        let studentId: String
        let termId: String
    }

    struct Session: Codable {
        let lastTime: String?
        let photoUrl: String?
        let tableCode: String
        let lastIp: String?
        let userType: String
        let scopes: [String]
        let loginCount: String
        let schoolCode: String
        let userId: String
        let userCode: String
        let userName: String
        let userNameCn: String
        let loginName: String
        let language: String
        let userRole: String
        let loginPage: Int
        let loginTime: String
        let moduleId: String
        let pagePermission: String

        enum CodingKeys: String, CodingKey {
            case lastTime
            case photoUrl
            case tableCode = "tableCode_"
            case lastIp
            case userType
            case scopes
            case loginCount
            case schoolCode
            case userId
            case userCode
            case userName
            case userNameCn
            case loginName
            case language
            case userRole
            case loginPage
            case loginTime
            case moduleId
            case pagePermission
        }
    }

    struct Version: Codable {
        let i18n: Int64
        let dd: Int64
        let parameter: Int64
    }

    struct Term: Codable {
        let beginDate: String
        let endDate: String
        let termId: String
    }

    private struct LessonClassInfo: Codable {
        let classInfoCode: String
        let classInfoId: String
        let classInfoName: String
        let lessonClassId: String
        let lessonTaskId: String
    }

    private struct StudentLessonTaskResponse: Codable {
        let success: Bool
        let data: [StudentLessonTask]?
        let errDesc: String
    }

    private struct StudentLessonTask: Codable {
        let bsid: String
        let lessonClassCode: String
    }

    private struct LessonCalendar: Codable {
        let courseId: String
        let courseCode: String
        let courseName: String
        let courseNameEn: String?
        let curriculumId: String
        let dayOfWeek: Int
        let facultyName: String
        let newFacultyName: String
        let lessonClassCode: String
        let lessonClassName: String
        let lessonTaskId: String
        let classRoomName: String
        let shiftClassRoomName: String
        let memo: String
        let sections: String
        let joinSections: Int?
        let week: String
        let classInfos: [LessonClassInfo]
    }

    private func prepareCookies() {
        cookies.forEach { cookie in
            AppAF.cookieStorage.setCookie(cookie)
        }
    }

    private func serializedUserInfoRequest() throws -> String {
        let request = UserInfoRequest(
            version: Version(
                i18n: 251211185520737,
                dd: 251211185522967,
                parameter: 260303145213804
            )
        )

        let data = try JSONEncoder().encode(request)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw APIError.internalError
        }

        return jsonString
    }

    private func serializedLessonCalendarRequest(termId: String, studentId: String) throws -> String {
        let request = LessonCalendarRequest(termId: termId, studentId: studentId)
        let data = try JSONEncoder().encode(request)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw APIError.internalError
        }

        return jsonString
    }

    private func serializedLessonTaskLookupRequest(termId: String, studentId: String) throws -> String {
        let request = LessonTaskLookupRequest(studentId: studentId, termId: termId)
        let data = try JSONEncoder().encode(request)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw APIError.internalError
        }

        return jsonString
    }

    private func getToken(scopes: [String]) async throws -> AccessToken {
        guard let token = tokens.first(where: { candidate in
            scopes.allSatisfy { scope in
                candidate.scopes.contains(scope)
            }
        }) else {
            throw WebAuthError.tokenWithScopeNotFound
        }

        if token.accessToken.isExpired {
            return try await token.accessToken.refresh()
        }

        return token.accessToken
    }

    private func getLessonTasks(termId: String, studentId: String) async throws -> [StudentLessonTask] {
        prepareCookies()

        let response = try await AppAF.session.request(
            Self.lessonTasksURL,
            parameters: [
                "_t": Int64(Date.now.timeIntervalSince1970 * 1000),
                "jsonString": try serializedLessonTaskLookupRequest(termId: termId, studentId: studentId)
            ],
            encoding: URLEncoding(destination: .queryString)
        )
        .validate(statusCode: 200...200)
        .serializingDecodable(StudentLessonTaskResponse.self)
        .value

        if !response.success {
            throw APIError.remoteError(response.errDesc.isEmpty ? "服务器未返回课程任务信息" : response.errDesc)
        }

        return response.data ?? []
    }

    private func getLessonDetail(bsid: String, accessToken: String) async throws -> SJTUOpenAPI.ClassSchedule? {
        let response = try await AppAF.session.request(
            "https://api.sjtu.edu.cn/v1/lesson/\(bsid)",
            parameters: [
                "access_token": accessToken
            ],
            encoding: URLEncoding(destination: .queryString)
        )
        .validate(statusCode: 200...200)
        .serializingDecodable(OpenApiResponse<SJTUOpenAPI.ClassSchedule>.self)
        .value

        if response.errno != 0 {
            throw APIError.remoteError(response.error)
        }

        return response.entities?.first
    }

    func getUserInfo() async throws -> UserInfoResponse {
        prepareCookies()

        return try await AppAF.session.request(
            Self.userInfoURL,
            parameters: [
                "jsonString": try serializedUserInfoRequest()
            ],
            encoding: URLEncoding(destination: .queryString),
        )
        .validate(statusCode: 200...200)
        .serializingDecodable(UserInfoResponse.self)
        .value
    }

    func getTerms() async throws -> [Term] {
        prepareCookies()

        let response = try await AppAF.session.request(
            Self.termsURL,
            parameters: [
                "_t": Int64.random(in: 0...Int64.max),
                "start": 0,
                "limie": 999999
            ],
            encoding: URLEncoding(destination: .queryString),
        )
        .validate(statusCode: 200...200)
        .serializingDecodable(TermResponse.self)
        .value

        if !response.success {
            throw APIError.remoteError(response.errDesc.isEmpty ? "服务器未返回学期信息" : response.errDesc)
        }

        guard let terms = response.data, !terms.isEmpty else {
            throw APIError.remoteError("服务器未返回学期信息")
        }

        return terms
    }

    func getCurrentTermId(for date: Date) async throws -> String {
        let selectedDay = date.startOfDay()

        for term in try await getTerms() {
            guard let beginDate = Date.fromFormat("yyyy-MM-dd", dateStr: term.beginDate),
                  let endDate = Date.fromFormat("yyyy-MM-dd", dateStr: term.endDate) else {
                throw APIError.internalError
            }

            if beginDate.startOfDay() <= selectedDay && selectedDay <= endDate.startOfDay() {
                return term.termId
            }
        }

        throw APIError.runtimeError("当前日期不属于任何有效学期")
    }

    func getSchedules(jointSemester: Semester, sjtuSemester: Semester?, termId: String, studentId: String) async throws -> [CourseClassSchedule] {
        prepareCookies()

        let response = try await AppAF.session.request(
            Self.schedulesURL,
            method: .post,
            parameters: [
                "jsonString": try serializedLessonCalendarRequest(termId: termId, studentId: studentId)
            ],
            encoding: URLEncoding.httpBody
        )
        .validate(statusCode: 200...200)
        .serializingDecodable([LessonCalendar].self)
        .value

        if response.isEmpty {
            return []
        }

        let lessonTasks = try await getLessonTasks(termId: termId, studentId: studentId)
        let bsidByLessonClassCode = Dictionary(
            lessonTasks.compactMap { task -> (String, String)? in
                let lessonClassCode = task.lessonClassCode.trimSpace()
                let bsid = task.bsid.trimSpace()
                guard !lessonClassCode.isEmpty, !bsid.isEmpty else {
                    return nil
                }
                return (lessonClassCode, bsid)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let accessToken = try await getToken(scopes: ["lessons"]).access_token
        let distinctBsids = Array(Set(bsidByLessonClassCode.values))
        var detailsByBsid: [String: SJTUOpenAPI.ClassSchedule] = [:]

        try await withThrowingTaskGroup(of: (String, SJTUOpenAPI.ClassSchedule?).self) { group in
            for bsid in distinctBsids {
                group.addTask {
                    (bsid, try await getLessonDetail(bsid: bsid, accessToken: accessToken))
                }
            }

            for try await (bsid, detail) in group {
                if let detail {
                    detailsByBsid[bsid] = detail
                }
            }
        }

        struct LessonSegment {
            let courseIdentity: String
            let teacherIdentity: String
            let day: Int
            let week: Int
            let startPeriod: Int
            var length: Int
            let classroom: String
        }

        func resolvedClassId(for lesson: LessonCalendar) throws -> String {
            if let lessonClassId = lesson.classInfos.first?.lessonClassId.trimSpace(), !lessonClassId.isEmpty {
                return lessonClassId
            }

            let classCode = lesson.lessonClassCode.trimSpace()
            if !classCode.isEmpty {
                return classCode
            }

            let lessonTaskId = lesson.lessonTaskId.trimSpace()
            if !lessonTaskId.isEmpty {
                return lessonTaskId
            }

            throw APIError.internalError
        }

        func resolvedCourseName(for lesson: LessonCalendar) -> String {
            let courseName = lesson.courseName.trimSpace()
            if !courseName.isEmpty {
                return courseName
            }

            if let courseNameEn = lesson.courseNameEn?.trimSpace(), !courseNameEn.isEmpty {
                return courseNameEn
            }

            let className = lesson.lessonClassName.trimSpace()
            if !className.isEmpty {
                return className
            }

            return lesson.courseCode.trimSpace()
        }

        func rawClassroom(for lesson: LessonCalendar) -> String {
            let shiftedClassroom = lesson.shiftClassRoomName.trimSpace()
            if !shiftedClassroom.isEmpty {
                return shiftedClassroom
            }

            let classroom = lesson.classRoomName.trimSpace()
            if !classroom.isEmpty {
                return classroom
            }

            return "未排教室"
        }

        func rawTeachers(for lesson: LessonCalendar) -> [String] {
            let candidates = [
                lesson.facultyName.trimSpace(),
                lesson.newFacultyName.trimSpace()
            ].filter { !$0.isEmpty }

            return Array(Set(candidates)).sorted()
        }

        func resolvedCourseIdentity(for lesson: LessonCalendar) -> String {
            let courseId = lesson.courseId.trimSpace()
            if !courseId.isEmpty {
                return courseId
            }

            let curriculumId = lesson.curriculumId.trimSpace()
            if !curriculumId.isEmpty {
                return curriculumId
            }

            let courseCode = lesson.courseCode.trimSpace()
            if !courseCode.isEmpty {
                return courseCode
            }

            return lesson.lessonTaskId.trimSpace()
        }

        func resolvedOrganization(for lesson: LessonCalendar, detail: SJTUOpenAPI.ClassSchedule?) -> Organization? {
            if let id = detail?.organize.id?.trimSpace(), !id.isEmpty,
               let name = detail?.organize.name?.trimSpace(), !name.isEmpty {
                return Organization(id: id, college: .joint, name: name)
            }

            guard let classInfo = lesson.classInfos.first else {
                return nil
            }

            let classInfoId = classInfo.classInfoId.trimSpace()
            let classInfoName = classInfo.classInfoName.trimSpace()
            guard !classInfoId.isEmpty, !classInfoName.isEmpty else {
                return nil
            }

            return Organization(id: classInfoId, college: .joint, name: classInfoName)
        }

        func resolvedDay(for lesson: LessonCalendar) throws -> Int {
            guard (1...7).contains(lesson.dayOfWeek) else {
                throw APIError.internalError
            }

            return lesson.dayOfWeek - 1
        }

        func resolvedPeriod(for lesson: LessonCalendar) throws -> Int {
            guard let section = Int(lesson.sections.trimSpace()) else {
                throw APIError.internalError
            }

            let period = section - 1
            guard CollegeTimeTable[.joint]?.contains(where: { $0.id == period }) == true else {
                throw APIError.internalError
            }

            return period
        }

        func resolvedLength(for lesson: LessonCalendar) -> Int {
            max(lesson.joinSections ?? 1, 1)
        }

        func resolvedWeeks(for lesson: LessonCalendar) throws -> [Int] {
            let weeks = Array(Set(lesson.week.split(separator: ",").compactMap { weekText in
                Int(weekText.trimmingCharacters(in: .whitespacesAndNewlines))
            })).sorted()

            guard !weeks.isEmpty else {
                throw APIError.internalError
            }

            return weeks.map { $0 - 1 }
        }

        func resolvedDetail(for lesson: LessonCalendar) -> SJTUOpenAPI.ClassSchedule? {
            let lessonClassCode = lesson.lessonClassCode.trimSpace()
            guard let bsid = bsidByLessonClassCode[lessonClassCode] else {
                return nil
            }

            return detailsByBsid[bsid]
        }

        func convertedSJTUWeek(from jointWeek: Int) -> Int? {
            guard let sjtuSemester else {
                return nil
            }

            let lessonDate = jointSemester.start_at.addWeeks(jointWeek)
            return lessonDate.weeksSince(sjtuSemester.start_at)
        }

        func resolvedTeachers(for lesson: LessonCalendar, detail: SJTUOpenAPI.ClassSchedule?) -> [String] {
            let detailTeachers = detail?.teachers.map { $0.name.trimSpace() }.filter { !$0.isEmpty } ?? []
            if !detailTeachers.isEmpty {
                return Array(Set(detailTeachers)).sorted()
            }

            return rawTeachers(for: lesson)
        }

        func resolvedClassroom(for lesson: LessonCalendar, detail: SJTUOpenAPI.ClassSchedule?, jointWeek: Int, day: Int, period: Int) -> String {
            if let sjtuWeek = convertedSJTUWeek(from: jointWeek),
               let classroom = detail?.classes.first(where: { classInfo in
                classInfo.schedule.week == sjtuWeek &&
                classInfo.schedule.day == day &&
                classInfo.schedule.period == period
            })?.classroom.name.trimSpace(),
            !classroom.isEmpty {
                return classroom
            }

            return rawClassroom(for: lesson)
        }

        func mergedSegments(for lessons: [LessonCalendar]) throws -> [LessonSegment] {
            let segments = try lessons.flatMap { lesson -> [LessonSegment] in
                let detail = resolvedDetail(for: lesson)
                let day = try resolvedDay(for: lesson)
                let startPeriod = try resolvedPeriod(for: lesson)
                let baseLength = resolvedLength(for: lesson)
                let teachers = resolvedTeachers(for: lesson, detail: detail)
                let teacherIdentity = teachers.joined(separator: "|")
                let courseIdentity = resolvedCourseIdentity(for: lesson)

                return try resolvedWeeks(for: lesson).map { week in
                    LessonSegment(
                        courseIdentity: courseIdentity,
                        teacherIdentity: teacherIdentity,
                        day: day,
                        week: week,
                        startPeriod: startPeriod,
                        length: baseLength,
                        classroom: resolvedClassroom(
                            for: lesson,
                            detail: detail,
                            jointWeek: week,
                            day: day,
                            period: startPeriod
                        )
                    )
                }
            }.sorted {
                if $0.week != $1.week {
                    return $0.week < $1.week
                }

                if $0.day != $1.day {
                    return $0.day < $1.day
                }

                if $0.courseIdentity != $1.courseIdentity {
                    return $0.courseIdentity < $1.courseIdentity
                }

                if $0.teacherIdentity != $1.teacherIdentity {
                    return $0.teacherIdentity < $1.teacherIdentity
                }

                if $0.classroom != $1.classroom {
                    return $0.classroom < $1.classroom
                }

                return $0.startPeriod < $1.startPeriod
            }

            var merged: [LessonSegment] = []

            for segment in segments {
                if var last = merged.last,
                   last.courseIdentity == segment.courseIdentity,
                   last.teacherIdentity == segment.teacherIdentity,
                   last.day == segment.day,
                   last.week == segment.week,
                   last.classroom == segment.classroom,
                   segment.startPeriod <= last.startPeriod + last.length {
                    let mergedEnd = max(last.startPeriod + last.length, segment.startPeriod + segment.length)
                    last.length = mergedEnd - last.startPeriod
                    merged[merged.count - 1] = last
                } else {
                    merged.append(segment)
                }
            }

            return merged
        }

        let groupedLessons = try Dictionary(grouping: response, by: { lesson in
            try resolvedClassId(for: lesson)
        })
        let palette = ClassColors.shuffled()

        return try groupedLessons.values.enumerated().map { index, lessons in
            guard let first = lessons.first else {
                throw APIError.internalError
            }

            let detail = resolvedDetail(for: first)
            let classId = try resolvedClassId(for: first)
            let organization = resolvedOrganization(for: first, detail: detail)
            let courseCode = first.courseCode.trimSpace()
            let classCode = detail?.code ?? first.lessonClassCode.trimSpace()
            let className = first.lessonClassName.trimSpace()
            let resolvedCourseCode = !courseCode.isEmpty ? courseCode : (classCode.isEmpty ? classId : classCode)
            let teachers = Array(Set(lessons.flatMap { lesson in
                resolvedTeachers(for: lesson, detail: resolvedDetail(for: lesson))
            })).sorted()

            var remarks: [String] = []
            for lesson in lessons {
                let memo = lesson.memo.trimSpace()
                if !memo.isEmpty && !remarks.contains(memo) {
                    remarks.append(memo)
                }
            }

            var seenScheduleKeys: Set<String> = []
            var schedules: [Schedule] = []

            for segment in try mergedSegments(for: lessons) {
                for offset in 0..<segment.length {
                    let period = segment.startPeriod + offset
                    guard CollegeTimeTable[.joint]?.contains(where: { $0.id == period }) == true else {
                        throw APIError.internalError
                    }

                    let key = "\(segment.week)-\(segment.day)-\(period)-\(segment.classroom)"
                    if !seenScheduleKeys.insert(key).inserted {
                        continue
                    }

                    schedules.append(
                        Schedule(
                            class_id: classId,
                            college: .joint,
                            classroom: segment.classroom,
                            day: segment.day,
                            period: period,
                            week: segment.week,
                            is_start: offset == 0,
                            length: offset == 0 ? segment.length : 0
                        )
                    )
                }
            }

            return CourseClassSchedule(
                course: Course(
                    code: resolvedCourseCode,
                    college: .joint,
                    name: resolvedCourseName(for: first)
                ),
                class_: Class(
                    id: classId,
                    college: .joint,
                    color: palette[index % palette.count],
                    course_code: resolvedCourseCode,
                    organization_id: organization?.id,
                    name: className.isEmpty ? resolvedCourseName(for: first) : className,
                    code: classCode.isEmpty ? classId : classCode,
                    teachers: teachers,
                    hours: detail?.hours ?? -1,
                    credits: detail?.credits ?? -1,
                    semester_id: jointSemester.id
                ),
                schedules: schedules.sorted {
                    if $0.week != $1.week {
                        return $0.week < $1.week
                    }

                    if $0.day != $1.day {
                        return $0.day < $1.day
                    }

                    return $0.period < $1.period
                },
                organization: organization,
                remarks: remarks.isEmpty ? nil : [
                    ClassRemark(
                        class_id: classId,
                        college: .joint,
                        remark: remarks.joined(separator: "\n")
                    )
                ]
            )
        }
    }
}

struct SJTUOpenAPI {
    var tokens: [TokenForScopes]?
    var token: AccessToken?
    
    struct ClassSchedule: Codable {
        let name, kind, bsid, code: String
        let course: ApiCourse
        let teachers: [ApiTeacher]
        let organize: ApiOrganize
        let hours, credits: Float
        let classes: [ApiClass]
    }

    struct ApiClass: Codable {
        let schedule: ApiSchedule
        let classroom: ApiClassroom
    }

    struct ApiTeacher: Codable {
        let name: String
        let kind: String
    }

    struct ApiClassroom: Codable {
        let name: String
        let kind: String
    }

    struct ApiSchedule: Codable {
        let kind: String
        let week, day, period: Int
    }

    struct ApiCourse: Codable {
        let code, name, kind: String
    }

    struct ApiOrganize: Codable {
        let id, name: String?
    }

    init(tokens: [TokenForScopes]) {
        self.tokens = tokens
    }

    init(token: AccessToken) {
        self.token = token
    }

    private func getToken(scopes: [String]) async throws -> AccessToken {
        if tokens != nil {
            let token = tokens!.first(where: { $0.scopes.contains(scopes) })
            guard let token else {
                throw WebAuthError.tokenWithScopeNotFound
            }
            if token.accessToken.isExpired {
                return try await token.accessToken.refresh()
            } else {
                return token.accessToken
            }
        } else {
            return token!
        }
    }

    func getUnicode() async throws -> Unicode {
        let token = try await getToken(scopes: ["unicode"])
        let response = try await AppAF.session.request(
            "https://api.sjtu.edu.cn/v1/unicode/identity",
            parameters: [
                "access_token": token.access_token
            ],
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable(OpenApiResponse<Unicode>.self).value
        
        if let entities = response.entities, entities.count > 0 {
            return entities[0]
        } else {
            throw APIError.remoteError("服务器未返回思源码")
        }
    }
    
    func getUnicodeTransactions(start: Int? = nil, limit: Int? = nil, beginDate: Int? = nil, endDate: Int? = nil) async throws -> [UnicodeTransaction] {
        let token = try await getToken(scopes: ["unicode"])
        var parameters: [String: any Codable] = [
            "access_token": token.access_token
        ]
        if let beginDate {
            parameters["beginDate"] = beginDate
        }
        if let endDate {
            parameters["endDate"] = endDate
        }
        if let start {
            parameters["start"] = start
        }
        if let limit {
            parameters["limit"] = limit
        }
        let response = try await AppAF.session.request(
            "https://api.sjtu.edu.cn/v1/unicode/transactions",
            parameters: parameters,
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable(OpenApiResponse<UnicodeTransaction>.self).value
                
        return response.entities ?? []
    }
    
    func getCampusCards() async throws -> [CampusCard] {
        let token = try await getToken(scopes: ["card"])
        let response = try await AppAF.session.request(
            "https://api.sjtu.edu.cn/v1/me/card",
            parameters: [
                "access_token": token.access_token
            ],
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable(OpenApiResponse<CampusCard>.self).value
        return response.entities ?? []
    }
    
    func chargeCampusCard(cardNo: String, amount: Int) async throws -> CardChargeResponse {
        let token = try await getToken(scopes: ["card"])
        let response = try await AppAF.session.request(
            "https://api.sjtu.edu.cn/v1/me/card/recharge",
            method: .post,
            parameters: [
                "access_token": token.access_token,
                "amount": amount,
                "cardNo": cardNo
            ],
            encoding: URLEncoding.httpBody,
            headers: [
                "User-Agent": "TaskCenterApp/3.4.6/iPhone16,1/ScreenFringe (iOS,iPhone,18.2; Scale/3.0)"
            ]
        ).serializingDecodable(OpenApiResponse<CardChargeResponse>.self).value
        if response.errno != 0 {
            throw APIError.remoteError(response.error)
        } else if let entities = response.entities, entities.count > 0 {
            return entities[0]
        } else {
            throw APIError.remoteError("服务器没有返回数据")
        }
    }
    
    func getChargeStatus(cardNo: String, orderId: Int64) async throws -> CardChargeStatus {
        let token = try await getToken(scopes: ["card"])
        let response = try await AppAF.session.request(
            "https://api.sjtu.edu.cn/v1/me/card/recharge",
            parameters: [
                "access_token": token.access_token,
                "cardNo": cardNo,
                "id": orderId
            ],
            encoding: URLEncoding(destination: .queryString),
            headers: [
                "User-Agent": "TaskCenterApp/3.4.6/iPhone16,1/ScreenFringe (iOS,iPhone,18.2; Scale/3.0)"
            ]
        ).serializingDecodable(OpenApiResponse<CardChargeStatus>.self).value
        if response.errno != 0 {
            throw APIError.remoteError(response.error)
        } else if let entities = response.entities, entities.count > 0 {
            return entities[0]
        } else {
            throw APIError.remoteError("服务器没有返回数据")
        }
    }
    
    func getUncompleteCharges(cardNo: String) async throws -> [CardChargeStatus] {
        let token = try await getToken(scopes: ["card"])
        let response = try await AppAF.session.request(
            "https://api.sjtu.edu.cn/v1/me/card/recharge",
            parameters: [
                "access_token": token.access_token,
                "cardNo": cardNo
            ],
            encoding: URLEncoding(destination: .queryString),
            headers: [
                "User-Agent": "TaskCenterApp/3.4.6/iPhone16,1/ScreenFringe (iOS,iPhone,18.2; Scale/3.0)"
            ]
        ).serializingDecodable(OpenApiResponse<CardChargeStatus>.self).value
        if response.errno != 0 {
            throw APIError.remoteError(response.error)
        }
        return response.entities ?? []
    }
    
    func getProfile() async throws -> Profile {
        let token = try await getToken(scopes: ["privacy"])
        let response = try await AppAF.session.request(
            "https://api.sjtu.edu.cn/v1/me/profile",
            parameters: [
                "access_token": token.access_token
            ],
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable(OpenApiResponse<Profile>.self).value
        
        if let entities = response.entities, entities.count > 0 {
            return entities[0]
        } else {
            throw APIError.remoteError("服务器未返回用户信息")
        }
    }
    
    func getCardPhoto(cardNo: String) async throws -> String? {
        let token = try await getToken(scopes: ["privacy"])
        let response = try await AppAF.session.request(
            "https://api.sjtu.edu.cn/v1/me/card/photo",
            parameters: [
                "access_token": token.access_token,
                "cardNo": cardNo,
                "urlOnly": true
            ],
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable(OpenApiResponse<CardPhoto>.self).value
        
        return response.entities?.first?.url
    }
    
    func getCardTransactions(cardNo: String, start: Int? = nil, limit: Int? = nil, beginDate: Int? = nil, endDate: Int? = nil) async throws -> (Int, [CardTransaction]) {
        let token = try await getToken(scopes: ["card"])
        var parameters: [String: any Codable] = [
            "access_token": token.access_token,
            "cardNo": cardNo,
        ]
        if let beginDate {
            parameters["beginDate"] = beginDate
        }
        if let endDate {
            parameters["endDate"] = endDate
        }
        if let start {
            parameters["start"] = start
        }
        if let limit {
            parameters["limit"] = limit
        }
        let response = try await AppAF.session.request(
            "https://api.sjtu.edu.cn/v1/me/card/transactions",
            parameters: parameters,
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable(OpenApiResponse<CardTransaction>.self).value
        return (response.total, response.entities ?? [])
    }
    
    func getSchedules(semester: Semester, sample: Bool = false) async throws -> [CourseClassSchedule] {
        var response: OpenApiResponse<ClassSchedule>?
        if sample {
            response = try await getScheduleSample()
        } else {
            let token = try await getToken(scopes: ["lessons"])
            response = try await AppAF.session.request(
                "https://api.sjtu.edu.cn/v1/me/lessons/\(semester.year)-\(semester.year + 1)-\(semester.semester)",
                parameters: [
                    "access_token": token.access_token
                ],
                encoding: URLEncoding(destination: .queryString)
            ).serializingDecodable(OpenApiResponse<ClassSchedule>.self).value
        }
        
        guard let response else {
            throw APIError.remoteError("无法获取课程列表")
        }
        
        let entities = response.entities ?? []
        let colors = ClassColors.randomColors(n: entities.count)
        return entities.enumerated().map { (index, entity) in
            var isStartFlags: [Int: Bool] = [:]
            
            return CourseClassSchedule(
                course: Course(code: entity.course.code, college: .sjtu, name: entity.course.name),
                class_: Class(id: entity.bsid, college: .sjtu, color: colors[index], course_code: entity.course.code, organization_id: entity.organize.id, name: entity.name, code: entity.code, teachers: entity.teachers.map { $0.name }, hours: entity.hours, credits: entity.credits, semester_id: semester.id),
                schedules: entity.classes.sorted {
                    if $0.schedule.week != $1.schedule.week {
                        return $0.schedule.week < $1.schedule.week
                    }

                    if $0.schedule.day != $1.schedule.day {
                        return $0.schedule.day < $1.schedule.day
                    }

                    return $0.schedule.period < $1.schedule.period
                }.enumerated().map { (index, schedule) in
                    var isStart: Bool = true
                    var length: Int = 0
                    
                    if let flag = isStartFlags[index], flag == false {
                        isStart = false
                        length = 0
                    } else {
                        isStart = true
                        var diff: Int = 1
                        while entity.classes.first(where: { class_ in
                            class_.schedule.week == schedule.schedule.week &&
                            class_.schedule.day == schedule.schedule.day &&
                            class_.classroom.name == schedule.classroom.name &&
                            class_.schedule.period == schedule.schedule.period + diff
                        }) != nil {
                            isStartFlags[index + diff] = false
                            diff += 1
                        }
                        length = diff
                    }
                    
                    return Schedule(class_id: entity.bsid, college: .sjtu, classroom: schedule.classroom.name, day: schedule.schedule.day, period: schedule.schedule.period, week: schedule.schedule.week, is_start: isStart, length: length)
                },
                organization: entity.organize.id != nil ? Organization(id: entity.organize.id!, college: .sjtu, name: entity.organize.name!) : nil
            )
        }
    }
}

struct ElectSysAPI {
    var cookies: [HTTPCookie]
    
    struct Exam {
        let courseName: String
        let courseCode: String
        var start: Date?
        var end: Date?
        let location: String
        let campus: String
        let isRebuild: Bool
        let examName: String
        let type: String?
        let order: Int
        let gradeType: String?
        let code: String
        let classCode: String
    }
    
    struct Grade {
        let id: String
        let courseName: String
        let courseCode: String
        let credit: String
        let score: String
        let grade: String?
        let remark: String?
        let teacher: String
    }

    struct GPAStatistics {
        let className: String
        let failedCourseCount: String
        let failedCredits: String
        let gpa: String
        let gpaRank: String
        let earnedCredits: String
        let academicPoints: String
        let academicPointsRank: String
        let totalCredits: String
        let courseScope: String?
        let collegeName: String?
        let majorName: String?
        let updatedAt: String?
    }
    
    private struct ElectSysResponse<T: Codable>: Codable {
        let currentPage, currentResult: Int
        let items: [T]
        let totalCount, totalPage, totalResult: Int
    }

    struct ElectSysExam: Codable {
        let ksfs: String?
        let ksmc, kssj: String
        let cdmc: String
        let cxbj, khfs: String?
        let cdxqmc, kcmc: String
        let kch, jxbmc, sjbh: String
        let rowID: Int

        enum CodingKeys: String, CodingKey {
            case ksfs, ksmc, kssj, kch, cxbj, khfs, cdmc, cdxqmc, kcmc, jxbmc, sjbh
            case rowID = "row_id"
        }
    }
    
    struct ElectSysGrade: Codable {
        let bfzcj: String
        let cj: String
        let jd: String?
        let jxbmc: String?
        let key: String
        let kch, kcmc: String
        let kcxzmc: String?
        let khfsmc: String?
        let kklxdm: String?
        let jsxm: String
        let ksxz: String
        let rowID: String
        let xf: String
        let cjbz, sskcmc: String?

        enum CodingKeys: String, CodingKey {
            case bfzcj, cj, jd, jxbmc, kch, kcmc, kcxzmc, khfsmc, kklxdm, ksxz, cjbz, sskcmc, xf, jsxm, key
            case rowID = "row_id"
        }
    }

    private struct ElectSysGPAStatistics: Codable {
        let bj: String
        let bjgms: String
        let bjgxf: String
        let czsj: String?
        let gpa: String
        let gpapm: String
        let hdxf: String
        let jgmc: String?
        let kcfw: String?
        let xjf: String
        let xjfpm: String
        let zxf: String
        let zymc: String?
    }

    private static let gpaStatisticsSuccessMessage = "统计成功！"
    private static let gpaStatisticsIgnoredGradeValues = "缓考,缓考(重考),尚未修读,暂不记录,中期退课,重考报名"
    private static let gpaStatisticsExcludedCourseIDs = "MARX1205,TH009,TH020,FCE62B4E084826EBE055F8163EE1DCCC"
    
    func openIdConnect() async throws {
        cookies.forEach { cookie in
            AppAF.cookieStorage.setCookie(cookie)
        }
        
        let response = try await AppAF.session.request("https://i.sjtu.edu.cn/jaccountlogin")
            .serializingString()
            .value
        if response.contains("无法登录") {
            throw APIError.noAccount
        }
    }
    
    func getExams(year: Int, semester: Int) async throws -> [Exam] {
        let response = try await AppAF.session.request(
            "https://i.sjtu.edu.cn/kwgl/kscx_cxXsksxxIndex.html?doType=query&gnmkdm=N358105",
            method: .post,
            parameters: [
                "xnm": year,
                "xqm": [3, 12, 16][semester - 1],
                "queryModel.showCount": 100,
                "queryModel.sortOrder": "asc"
            ],
            encoding: URLEncoding.httpBody
        ).serializingDecodable(ElectSysResponse<ElectSysExam>.self).value

        let date = /([0-9]+)-([0-9]+)-([0-9]+)\(([0-9]+):([0-9]+)-([0-9]+):([0-9]+)\)/
        return response.items.map { exam in
            var _exam = Exam(
                courseName: exam.kcmc,
                courseCode: exam.kch,
                start: nil,
                end: nil,
                location: exam.cdmc,
                campus: exam.cdxqmc,
                isRebuild: exam.cxbj != "否",
                examName: exam.ksmc,
                type: exam.ksfs,
                order: exam.rowID,
                gradeType: exam.khfs,
                code: exam.sjbh,
                classCode: exam.jxbmc
            )
            
            if let examDate = exam.kssj.firstMatch(of: date) {
                _exam.start = Calendar.iso8601.date(from: .init(year: Int(examDate.1), month: Int(examDate.2), day: Int(examDate.3), hour: Int(examDate.4), minute: Int(examDate.5)))
                _exam.end = Calendar.iso8601.date(from: .init(year: Int(examDate.1), month: Int(examDate.2), day: Int(examDate.3), hour: Int(examDate.6), minute: Int(examDate.7)))
            }
            return _exam
        }
    }
    
    func getGrades(year: Int, semester: Int) async throws -> [Grade] {        
        let response = try await AppAF.session.request(
            "https://i.sjtu.edu.cn/cjcx/cjcx_cxXsgrcj.html?doType=query&gnmkdm=N305005",
            method: .post,
            parameters: [
                "xnm": year,
                "xqm": [3, 12, 16][semester - 1],
                "queryModel.showCount": 100,
                "queryModel.sortOrder": "asc"
            ],
            encoding: URLEncoding.httpBody
        ).serializingDecodable(ElectSysResponse<ElectSysGrade>.self).value
        
        return response.items.map { grade in
            Grade(
                id: grade.key,
                courseName: grade.kcmc,
                courseCode: grade.kch,
                credit: grade.xf,
                score: grade.cj,
                grade: grade.jd,
                remark: grade.cjbz,
                teacher: grade.jsxm
            )
        }
    }

    func getGPAStatistics(
        startYear: Int? = nil,
        startSemester: Int? = nil,
        endYear: Int? = nil,
        endSemester: Int? = nil
    ) async throws -> GPAStatistics? {
        let range = try Self.resolveGPAStatisticsRange(
            startYear: startYear,
            startSemester: startSemester,
            endYear: endYear,
            endSemester: endSemester
        )
        let commonParameters = Self.gpaStatisticsCommonParameters(
            startTermCode: range.startTermCode,
            endTermCode: range.endTermCode
        )

        let triggerResponseData = try await AppAF.session.request(
            "https://i.sjtu.edu.cn/cjpmtj/gpapmtj_tjGpapmtj.html?gnmkdm=N309131",
            method: .post,
            parameters: commonParameters,
            encoding: URLEncoding.httpBody
        ).serializingData().value

        let triggerResponse = try Self.parseJSONStringResponse(triggerResponseData)
        guard triggerResponse == Self.gpaStatisticsSuccessMessage else {
            throw APIError.remoteError(triggerResponse)
        }

        var queryParameters = commonParameters
        queryParameters["_search"] = "false"
        queryParameters["nd"] = Int64(Date.now.timeIntervalSince1970 * 1000)
        queryParameters["queryModel.showCount"] = 15
        queryParameters["queryModel.currentPage"] = 1
        queryParameters["queryModel.sortName"] = " "
        queryParameters["queryModel.sortOrder"] = "asc"
        queryParameters["time"] = 2

        let response = try await AppAF.session.request(
            "https://i.sjtu.edu.cn/cjpmtj/gpapmtj_cxGpaxjfcxIndex.html?doType=query&gnmkdm=N309131",
            method: .post,
            parameters: queryParameters,
            encoding: URLEncoding.httpBody
        ).serializingDecodable(ElectSysResponse<ElectSysGPAStatistics>.self).value

        guard let item = response.items.first else {
            return nil
        }

        return GPAStatistics(
            className: item.bj,
            failedCourseCount: item.bjgms,
            failedCredits: item.bjgxf,
            gpa: item.gpa,
            gpaRank: item.gpapm,
            earnedCredits: item.hdxf,
            academicPoints: item.xjf,
            academicPointsRank: item.xjfpm,
            totalCredits: item.zxf,
            courseScope: item.kcfw,
            collegeName: item.jgmc,
            majorName: item.zymc,
            updatedAt: item.czsj
        )
    }

    private static func resolveGPAStatisticsRange(
        startYear: Int?,
        startSemester: Int?,
        endYear: Int?,
        endSemester: Int?
    ) throws -> (startTermCode: String, endTermCode: String) {
        let startCode = try gpaStatisticsTermCode(
            year: startYear,
            semester: startSemester,
            label: "起始"
        )
        let endCode = try gpaStatisticsTermCode(
            year: endYear,
            semester: endSemester,
            label: "结束"
        )

        if let startCode, let endCode, startCode > endCode {
            throw APIError.runtimeError("起始学期不能晚于结束学期。")
        }

        return (
            startTermCode: startCode.map(String.init) ?? "",
            endTermCode: endCode.map(String.init) ?? ""
        )
    }

    private static func gpaStatisticsTermCode(
        year: Int?,
        semester: Int?,
        label: String
    ) throws -> Int? {
        switch (year, semester) {
        case (nil, nil):
            return nil
        case let (year?, semester?):
            guard (1...3).contains(semester) else {
                throw APIError.runtimeError("\(label)学期参数无效，必须是 1（秋）、2（春）或 3（夏）。")
            }

            let xqm = [3, 12, 16][semester - 1]
            return year * 100 + xqm
        default:
            throw APIError.runtimeError("\(label)学期必须同时提供 year 和 semester。")
        }
    }

    private static func gpaStatisticsCommonParameters(
        startTermCode: String,
        endTermCode: String
    ) -> Parameters {
        [
            "qsXnxq": startTermCode,
            "zzXnxq": endTermCode,
            "tjgx": 0,
            "alsfj": "",
            "sspjfblws": 9,
            "pjjdblws": 9,
            "bjpjf": gpaStatisticsIgnoredGradeValues,
            "bjjd": gpaStatisticsIgnoredGradeValues,
            "kch_ids": gpaStatisticsExcludedCourseIDs,
            "bcjkc_id": "",
            "bcjkz_id": "",
            "cjkz_id": "",
            "cjxzm": "zhyccj",
            "kcfw": "hxkc",
            "tjfw": "njzy",
            "xjzt": 1
        ]
    }

    private static func parseJSONStringResponse(_ data: Data) throws -> String {
        if let value = try? JSONDecoder().decode(String.self, from: data) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        throw APIError.internalError
    }
}

struct CanvasAPI {
    var cookies: [HTTPCookie]?
    var token: String?
    let graphQLURL = URL(string: "https://oc.sjtu.edu.cn/api/graphql")!
    var client: ApolloClient? = nil
    
    struct CanvasLMSToken {
        var id: String
        var appName: String
        var purpose: String
        var token: String
    }
    
    struct LMSToken: Codable {
        let userID: Int
        let workflowState: String
        let rootAccountID, id, developerKeyID: Int
        let lastUsedAt, expiresAt: String?
        let purpose: String
        let createdAt, updatedAt: String
        let appName, visibleToken: String
        
        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case workflowState = "workflow_state"
            case rootAccountID = "root_account_id"
            case id
            case developerKeyID = "developer_key_id"
            case lastUsedAt = "last_used_at"
            case expiresAt = "expires_at"
            case purpose
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case appName = "app_name"
            case visibleToken = "visible_token"
        }
    }
    
    struct Event: Codable {
        let title: String
        let description: String?
        let type: String
        let assignment: Assignment?
    }
    
    struct Assignment: Codable {
        let id: Int
    }
    
    func openIdConnect() async throws {
        guard let cookies else { throw APIError.sessionExpired }
        
        cookies.forEach { cookie in
            AppAF.cookieStorage.setCookie(cookie)
        }
        
        let response = try await AppAF.session.request("https://oc.sjtu.edu.cn/login/openid_connect")
            .serializingString()
            .value
        if response.contains("以下用户没有Canvas") {
            throw APIError.noAccount
        }
    }
    
    init(cookies: [HTTPCookie]) {
        self.cookies = cookies
    }
    
    init(token: String) {
        self.token = token
        let client = URLSessionClient()
        let cache = InMemoryNormalizedCache()
        let store = ApolloStore(cache: cache)
        let provider = DefaultInterceptorProvider(client: client, shouldInvalidateClientOnDeinit: false, store: store)
        let transport = RequestChainNetworkTransport(
            interceptorProvider: provider,
            endpointURL: graphQLURL,
            additionalHeaders: ["Authorization": "Bearer \(token)"]
        )
        
        self.client = ApolloClient(networkTransport: transport, store: store)
    }
    
    func getCSRFToken() throws -> String {
        var csrfToken: String?
        
        for cookies in AppAF.cookieStorage.cookies ?? [] {
            if cookies.name == "_csrf_token", cookies.domain == "oc.sjtu.edu.cn" {
                csrfToken = cookies.value.removingPercentEncoding
            }
        }
        
        guard let csrfToken else {
            throw APIError.runtimeError("获取 CSRF 错误")
        }
        
        return csrfToken
    }
    
    func getTokens() async throws -> [CanvasLMSToken] {
        let response = try await AppAF.session.request("https://oc.sjtu.edu.cn/profile/settings")
            .serializingString()
            .value
        
        let doc: Document = try SwiftSoup.parse(response)
        
        var tokens: [CanvasLMSToken] = []
        for tokenRow in try doc.select("tr.access_token:not(.blank)") {
            var token = CanvasLMSToken(id: "", appName: "", purpose: "", token: "")
            do {
                if let appName = try tokenRow.select("td.app_name").first() {
                    token.appName = try appName.text()
                }
                
                if let purpose = try tokenRow.select("td.purpose").first() {
                    token.purpose = try purpose.text()
                }
                
                if let tokenLink = try tokenRow.select("a.show_token_link").first() {
                    let link = try tokenLink.attr("rel")
                    token.id = String(link.split(separator: "/").last!)
                }
            } catch {
                continue
            }
            tokens.append(token)
        }
        
        return tokens
    }
    
    func deleteToken(tokenId: String) async throws {
        let csrfToken = try getCSRFToken()
        
        _ = try await AppAF.session.request(
            "https://oc.sjtu.edu.cn/profile/tokens/\(tokenId)",
            method: .post,
            parameters: [
                "_method": "DELETE"
            ],
            encoding: URLEncoding.httpBody,
            headers: [
                "X-Csrf-Token": csrfToken
            ]
        )
        .serializingData()
        .value
    }
    
    func regenerateToken(tokenId: String) async throws -> CanvasLMSToken {
        let csrfToken = try getCSRFToken()
        
        let response = try await AppAF.session.request(
            "https://oc.sjtu.edu.cn/profile/tokens/\(tokenId)",
            method: .post,
            parameters: [
                "access_token[regenerate]": "1",
                "_method": "PUT"
            ],
            encoding: URLEncoding.httpBody,
            headers: [
                "X-Csrf-Token": csrfToken
            ]
        )
            .serializingDecodable(LMSToken.self)
            .value
        
        return CanvasLMSToken(id: String(response.id), appName: response.appName, purpose: response.purpose, token: response.visibleToken)
    }
    
    func generateToken() async throws -> CanvasLMSToken {
        let csrfToken = try getCSRFToken()
        
        let response = try await AppAF.session.request(
            "https://oc.sjtu.edu.cn/profile/tokens",
            method: .post,
            parameters: [
                "access_token[purpose]": "MySJTU",
                "purpose": "MySJTU",
                "access_token[permanent_expires_at]": "",
                "permanent_expires_at": "",
                "_method": "post"
            ],
            encoding: URLEncoding.httpBody,
            headers: [
                "X-Csrf-Token": csrfToken
            ]
        )
            .serializingDecodable(LMSToken.self)
            .value
        
        return CanvasLMSToken(id: String(response.id), appName: response.appName, purpose: response.purpose, token: response.visibleToken)
    }
    
    func getAllClasses() async throws -> [CanvasSchema.GetAllClassesQuery.Data.AllCourse] {
        guard client != nil else {
            throw APIError.noAccount
        }
        
        let query = CanvasSchema.GetAllClassesQuery()
        
        for try await result in client!.fetch(query: query) {
            if let courses = result.data?.allCourses {
                return courses
            }
        }
        
        return []
    }
    
    func getClass(classId: String) async throws -> CanvasSchema.GetClassQuery.Data.Course? {
        guard client != nil else {
            throw APIError.noAccount
        }
        
        let query = CanvasSchema.GetClassQuery(classId: classId)
        
        for try await result in client!.fetch(query: query) {
            if let course = result.data?.course {
                return course
            }
        }
        
        return nil
    }
    
    func getClassAssignments(classId: String) async throws -> [CanvasSchema.GetClassAssignmentsQuery.Data.Course.AssignmentsConnection.Node] {
        guard client != nil else {
            throw APIError.noAccount
        }
        
        let query = CanvasSchema.GetClassAssignmentsQuery(classId: classId)
        var assignments: [CanvasSchema.GetClassAssignmentsQuery.Data.Course.AssignmentsConnection.Node] = []
        
        for try await result in client!.fetch(query: query) {
            if let nodes = result.data?.course?.assignmentsConnection?.nodes {
                for node in nodes {
                    if let node {
                        assignments.append(node)
                    }
                }
            }
        }
        
        return assignments
    }
    
    func getAssignmentDetail(assignmentId: String) async throws -> CanvasSchema.GetAssignmentDetailQuery.Data.Assignment? {
        guard client != nil else {
            throw APIError.noAccount
        }
        
        let query = CanvasSchema.GetAssignmentDetailQuery(assignmentId: assignmentId)
        
        for try await result in client!.fetch(query: query) {
            return result.data?.assignment
        }
        
        return nil
    }
    
    func getAssignments(assignmentIds: [Int]) async throws -> [CanvasSchema.GetAssignmentQuery.Data.Assignment] {
        guard let client else {
            throw APIError.noAccount
        }
        
        return await withTaskGroup(of: CanvasSchema.GetAssignmentQuery.Data.Assignment?.self) { group in
            var results: [CanvasSchema.GetAssignmentQuery.Data.Assignment] = []
            
            for id in assignmentIds {
                group.addTask {
                    do {
                        let query = CanvasSchema.GetAssignmentQuery(assignmentId: String(id))
                        for try await result in client.fetch(query: query) {
                            if let assignment = result.data?.assignment {
                                return assignment
                            }
                        }
                    } catch {
                        print(error)
                    }
                    
                    return nil
                }
            }
            
            for await result in group {
                if let result {
                    results.append(result)
                }
            }
            
            return results
        }
    }
    
    func getUpcomingEvents() async throws -> [Event] {
        guard let token else {
            throw APIError.noAccount
        }

        let response = await AppAF.session.request(
            "https://oc.sjtu.edu.cn/api/v1/users/self/upcoming_events",
            headers: [
                "Authorization": "Bearer \(token)"
            ]
        ).serializingDecodable([Event].self).response

        if response.response?.statusCode == 401 {
            throw APIError.sessionExpired
        }

        return try response.result.get()
    }
    
    func checkToken() async throws {
        guard let token else {
            throw APIError.noAccount
        }
        
        let response = await AppAF.session.request(
            "https://oc.sjtu.edu.cn/api/v1/users/self",
            headers: [
                "Authorization": "Bearer \(token)"
            ]
        ).serializingData().response
        
        if response.response?.statusCode == 401 {
            throw APIError.sessionExpired
        } else if response.response?.statusCode != 200 {
            throw APIError.remoteError("状态码错误")
        }
    }
}
