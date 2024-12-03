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

enum APIError: Error {
    case sessionExpired
    case badCSRF
    case noAccount
    case getCourseInfoFailed
    case internalError
}

private struct semester: Codable {
    let id: String
    let year, semester: Int
    let start_date, end_date: String
}

private struct semesterResponse: Codable {
    let updated_at: Double
    let semesters: [semester]
}

func getSemesters(college: College) async throws -> [Semester] {
    let url = college == .sjtu ? "https://s3.jcloud.sjtu.edu.cn/9fd44bb76f604e8597acfcceada7cb83-tongqu/class_table/calendar.json"
        :
        "https://s3.jcloud.sjtu.edu.cn/9fd44bb76f604e8597acfcceada7cb83-tongqu/class_table/calendar_shsmu.json"

    let response = try await AF.request(
        url,
        parameters: [
            "r": Date.now.timeIntervalSince1970
        ],
        encoding: URLEncoding(destination: .queryString)
    ).serializingDecodable(semesterResponse.self).value

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    return response.semesters.map {
        Semester(id: $0.id, college: college, year: $0.year, semester: $0.semester, start_at: Date.fromFormat("yyyy-MM-dd", dateStr: $0.start_date)!.startOfDay(), end_at: Date.fromFormat("yyyy-MM-dd", dateStr: $0.end_date)!.startOfDay().addDays(1).startOfDay())
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
        let curriculum, courseCode: String
        let courseCount: Int
        let classroomAcademy, start: String
        let curriculumType: String
        let mcsid: String
        let csid: Int?
        let curriculumID: Int
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
        let id, teachingCalendarID: Int
        let curriculumScheduleIDs: String
        let classTime: String
        let classHour, curriculumType: Int
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
    
    func getSchedules(semester: Semester) async throws -> [([String: String], CourseClassSchedule)] {
        let start = semester.start_at.formattedDate()
        let end = semester.end_at.formattedDate()
                
        cookies.forEach { cookie in
            AF.session.configuration.httpCookieStorage?.setCookie(cookie)
        }
        
        _ = try await AF.request(
            "\(baseUrl)/Home/Timetable"
        ).serializingString().value
        
        let response = try await AF.request(
            "\(baseUrl)/Home/GetCurriculumTable",
            parameters: [
                "Start": start,
                "End": end
            ],
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable(Response<SHSMUSchedule>.self).value
        
        var classes: [([String: String], CourseClassSchedule)] = []
        let colors = ClassColors.randomColors()
        
        for schedule in response.list {
            var classIndex = classes.firstIndex(where: { $0.1.class_.id == String(schedule.curriculumID) })
            if classIndex == nil {
                classes.append((
                    [
                        "MCSID": schedule.mcsid,
                        "CSID": schedule.csid != nil ? String(schedule.csid!) : "null",
                        "CurriculumID": String(schedule.curriculumID),
                        "XXKMID": schedule.xxkmid != nil ? String(schedule.xxkmid!) : "null",
                        "CurriculumType": schedule.curriculumType
                    ],
                    CourseClassSchedule(
                        course: Course(code: schedule.courseCode.trimSpace(), college: .shsmu, name: schedule.curriculum.trimSpace()),
                        class_: Class(
                            id: String(schedule.curriculumID),
                            college: .shsmu,
                            color: colors[classes.count],
                            course_code: schedule.courseCode.trimSpace(),
                            name: schedule.curriculum.trimSpace(),
                            code: schedule.courseCode.trimSpace(),
                            teachers: [],
                            hours: -1,
                            credits: 01,
                            semester_id: semester.id
                        ),
                        schedules: []
                    )
                ))
                classIndex = classes.count - 1
            }
            
            if let startPeriod = getPeriodByTime(college: .shsmu, time: String(schedule.start.split(separator: "T")[1])) {
                for i in 0..<schedule.courseCount {
                    if let start = Date.fromFormat("yyyy-MM-dd'T'HH:mm:ss", dateStr: schedule.start, calendar: .iso8601) {
                        classes[classIndex!].1.schedules.append(Schedule(
                            class_id: classes[classIndex!].1.class_.id,
                            college: .shsmu,
                            classroom: schedule.classroomAcademy.trimSpace(),
                            day: (start.get(.weekday) + 5) % 7,
                            period: (startPeriod.id >= 5 ? startPeriod.id + 1 : startPeriod.id) + i,
                            week: start.weeksSince(semester.start_at),
                            is_start: i == 0,
                            length: i == 0 ? schedule.courseCount : 0
                        ))
                    }
                }
            }
        }

        return classes
    }
    
    func getCourseInfo(schedule: ([String: String], CourseClassSchedule)) async throws -> CourseClassSchedule {
        cookies.forEach { cookie in
            AF.session.configuration.httpCookieStorage?.setCookie(cookie)
        }
        
        print(schedule.0)
        let response = try await AF.request(
            "\(baseUrl)/Home/GetCalendarTable",
            parameters: schedule.0,
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable([SHSMUCourse].self).value
        
        if response.count == 0 {
            throw APIError.getCourseInfoFailed
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
            AF.session.configuration.httpCookieStorage?.setCookie(cookie)
        }
        
        let _ = try await AF.request("https://yjs.sjtu.edu.cn/gsapp/sys/wdkbapp/*default/index.do")
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
        
        let schedules = try await AF.request(
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
        let response = try await AF.request(
            "https://api.sjtu.edu.cn/v1/unicode/identity",
            parameters: [
                "access_token": token.access_token
            ],
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable(OpenApiResponse<Unicode>.self).value
        return response.entities[0]
    }
    
    func getSchedules(semester: Semester, sample: Bool = false) async throws -> [CourseClassSchedule] {
        var response: OpenApiResponse<ClassSchedule>?
        if sample {
            response = try await getScheduleSample()
        } else {
            let token = try await getToken(scopes: ["lessons"])
            response = try await AF.request(
                "https://api.sjtu.edu.cn/v1/me/lessons/\(semester.year)-\(semester.year + 1)-\(semester.semester)",
                parameters: [
                    "access_token": token.access_token
                ],
                encoding: URLEncoding(destination: .queryString)
            ).serializingDecodable(OpenApiResponse<ClassSchedule>.self).value
        }
        
        guard let response else {
            throw APIError.internalError
        }
        
        let colors = ClassColors.randomColors(n: response.entities.count)
        return response.entities.enumerated().map { (index, entity) in
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
    
    func openIdConnect() async throws {
        guard let cookies else { throw APIError.sessionExpired }
        
        cookies.forEach { cookie in
            AF.session.configuration.httpCookieStorage?.setCookie(cookie)
        }
        
        let response = try await AF.request("https://oc.sjtu.edu.cn/login/openid_connect")
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
        
        for cookies in AF.session.configuration.httpCookieStorage?.cookies ?? [] {
            if cookies.name == "_csrf_token", cookies.domain == "oc.sjtu.edu.cn" {
                csrfToken = cookies.value.removingPercentEncoding
            }
        }
        
        guard let csrfToken else {
            throw APIError.badCSRF
        }
        
        return csrfToken
    }
    
    func getTokens() async throws -> [CanvasLMSToken] {
        let response = try await AF.request("https://oc.sjtu.edu.cn/profile/settings")
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
        
        _ = try await AF.request(
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
        
        let response = try await AF.request(
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
        
        let response = try await AF.request(
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
    
    func checkToken() async throws {
        guard let token else {
            throw APIError.noAccount
        }
        
        let response = await AF.request(
            "https://oc.sjtu.edu.cn/api/v1/users/self",
            headers: [
                "Authorization": "Bearer \(token)"
            ]
        ).serializingData().response
        
        
        if response.response?.statusCode == 401 {
            throw APIError.sessionExpired
        } else if response.response?.statusCode != 200 {
            throw APIError.internalError
        }
    }
}
