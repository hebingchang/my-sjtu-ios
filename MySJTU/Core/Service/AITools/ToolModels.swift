//
//  ToolModels.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

struct FunctionParametersSchema: Encodable {
    let type: String
    let properties: [String: Property]
    let required: [String]
    let additionalProperties: Bool

    var supportsStrictMode: Bool {
        Set(required) == Set(properties.keys)
    }

    struct Property: Encodable {
        let type: String
        let description: String
        let enumValues: [String]?
        let format: String?

        init(
            type: String,
            description: String,
            enumValues: [String]? = nil,
            format: String? = nil
        ) {
            self.type = type
            self.description = description
            self.enumValues = enumValues
            self.format = format
        }

        enum CodingKeys: String, CodingKey {
            case type
            case description
            case enumValues = "enum"
            case format
        }
    }

    static let capabilityProbe = Self(
        type: "object",
        properties: [
            "message": .init(
                type: "string",
                description: "一段简短的确认文本。"
            )
        ],
        required: ["message"],
        additionalProperties: false
    )

    static let emptyObject = Self(
        type: "object",
        properties: [:],
        required: [],
        additionalProperties: false
    )

    static let currentDataSourceSemester = Self(
        type: "object",
        properties: [
            "comparison": .init(
                type: "string",
                description: "与给定日期比较的方向。必须是“早于”、“等于”或“晚于”。",
                enumValues: ["早于", "等于", "晚于"]
            ),
            "date": .init(
                type: "string",
                description: "要查询的日期，格式为 YYYY-MM-DD。",
                format: "date"
            )
        ],
        required: ["comparison", "date"],
        additionalProperties: false
    )

    static let currentDataSourceSchedules = Self(
        type: "object",
        properties: [
            "date": .init(
                type: "string",
                description: "要查询日程的日期，格式为 YYYY-MM-DD。",
                format: "date"
            )
        ],
        required: ["date"],
        additionalProperties: false
    )

    static let academicYearSemester = Self(
        type: "object",
        properties: [
            "year": .init(
                type: "integer",
                description: "要查询的学年年份，例如 2025。"
            ),
            "semester": .init(
                type: "string",
                description: "要查询的学期季别，必须是“秋”、“春”或“夏”。",
                enumValues: ["秋", "春", "夏"]
            )
        ],
        required: ["year", "semester"],
        additionalProperties: false
    )

    static let examAndGradeStatisticsRange = Self(
        type: "object",
        properties: [
            "start_year": .init(
                type: "integer",
                description: "统计开始学期的学年年份，例如 2025。必须与 start_semester 成对提供；若只提供 start_year/start_semester 且省略结束学期，则统计从该学期开始的全部学期。"
            ),
            "start_semester": .init(
                type: "string",
                description: "统计开始学期的季别，必须是“秋”、“春”或“夏”。必须与 start_year 成对提供。",
                enumValues: ["秋", "春", "夏"]
            ),
            "end_year": .init(
                type: "integer",
                description: "统计结束学期的学年年份，例如 2025。必须与 end_semester 成对提供；若只提供 end_year/end_semester 且省略开始学期，则统计截至该学期（含）的全部学期。"
            ),
            "end_semester": .init(
                type: "string",
                description: "统计结束学期的季别，必须是“秋”、“春”或“夏”。必须与 end_year 成对提供。",
                enumValues: ["秋", "春", "夏"]
            )
        ],
        required: [],
        additionalProperties: false
    )

    static let selfStudyBuildingRooms = Self(
        type: "object",
        properties: [
            "building_name": .init(
                type: "string",
                description: "要查询的教学楼名称，例如“上院”“中院”“下院”。工具会在后台获取可用教学楼列表并做名称匹配。"
            )
        ],
        required: ["building_name"],
        additionalProperties: false
    )

    static let selfStudyRoomStatus = Self(
        type: "object",
        properties: [
            "room_id": .init(
                type: "integer",
                description: "要查询的教室 ID，可从教学楼教室查询结果中的 id 获取。"
            )
        ],
        required: ["room_id"],
        additionalProperties: false
    )

    static let campusCardDateRange = Self(
        type: "object",
        properties: [
            "card_no": .init(
                type: "string",
                description: "要查询的校园卡卡号。必须是当前 jAccount 账号下的有效校园卡卡号。"
            ),
            "start_date": .init(
                type: "string",
                description: "查询开始日期，格式为 YYYY-MM-DD。",
                format: "date"
            ),
            "end_date": .init(
                type: "string",
                description: "查询结束日期，格式为 YYYY-MM-DD。",
                format: "date"
            )
        ],
        required: ["card_no", "start_date", "end_date"],
        additionalProperties: false
    )

    static let scheduleNotification = Self(
        type: "object",
        properties: [
            "year": .init(
                type: "integer",
                description: "通知时间的北京时间年份，例如 2026。"
            ),
            "month": .init(
                type: "integer",
                description: "通知时间的北京时间月份，取值范围为 1 到 12。"
            ),
            "day": .init(
                type: "integer",
                description: "通知时间的北京时间日期。"
            ),
            "hour": .init(
                type: "integer",
                description: "通知时间的北京时间小时，使用 24 小时制，取值范围为 0 到 23。"
            ),
            "minute": .init(
                type: "integer",
                description: "通知时间的北京时间分钟，取值范围为 0 到 59。"
            ),
            "content": .init(
                type: "string",
                description: "通知正文内容。"
            )
        ],
        required: ["year", "month", "day", "hour", "minute", "content"],
        additionalProperties: false
    )

    static let deletePendingNotifications = Self(
        type: "object",
        properties: [
            "notification_id": .init(
                type: "string",
                description: "要删除的通知 ID。省略时删除全部尚未触发的通知。"
            )
        ],
        required: [],
        additionalProperties: false
    )

    enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case additionalProperties = "additionalProperties"
    }
}

struct CurrentDataSourceSemesterToolArguments: Decodable {
    let comparison: String
    let date: String
}

struct CurrentDataSourceSchedulesToolArguments: Decodable {
    let date: String
}

struct AcademicYearSemesterToolArguments: Decodable {
    let year: Int
    let semester: String
}

struct ExamAndGradeStatisticsRangeToolArguments: Decodable {
    let startYear: Int?
    let startSemester: String?
    let endYear: Int?
    let endSemester: String?

    enum CodingKeys: String, CodingKey {
        case startYear = "start_year"
        case startSemester = "start_semester"
        case endYear = "end_year"
        case endSemester = "end_semester"
    }
}

struct SelfStudyBuildingRoomsToolArguments: Decodable {
    let buildingName: String

    enum CodingKeys: String, CodingKey {
        case buildingName = "building_name"
    }
}

struct SelfStudyRoomStatusToolArguments: Decodable {
    let roomId: Int

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
    }
}

struct CampusCardDateRangeToolArguments: Decodable {
    let cardNo: String
    let startDate: String
    let endDate: String

    enum CodingKeys: String, CodingKey {
        case cardNo = "card_no"
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

struct ScheduleNotificationToolArguments: Decodable {
    let year: Int
    let month: Int
    let day: Int
    let hour: Int
    let minute: Int
    let content: String
}

struct DeletePendingNotificationsToolArguments: Decodable {
    let notificationId: String?

    enum CodingKeys: String, CodingKey {
        case notificationId = "notification_id"
    }
}

struct ToolStatusPayload: Codable {
    let text: String
    let functionName: String?
    let category: AIToolCallCategory?
    let invocationKey: String?

    enum CodingKeys: String, CodingKey {
        case text
        case functionName = "function_name"
        case category
        case invocationKey = "invocation_key"
    }
}

struct OpenJAccountAccountToolResult: Encodable {
    let ok: Bool = true
    let destination: String
}

struct UserProfileToolResult: Encodable {
    let name: String?
    let code: String?
    let userTypeName: String?
    let organize: String?
    let classNo: String?
    let admissionDate: String?
    let trainLevel: String?
    let graduateDate: String?
}

struct CampusCardInformationToolResult: Encodable {
    let ok: Bool = true
    let jAccountAccount: String
    let userName: String
    let userCode: String
    let cardCount: Int
    let cards: [Card]

    struct Card: Encodable {
        let cardNo: String
        let cardId: String
        let bankNo: String
        let expireDate: String
        let cardType: String
        let cardBalance: Double
        let transBalance: Int
        let lost: Bool
        let frozen: Bool
        let organizationName: String?

        enum CodingKeys: String, CodingKey {
            case cardNo = "card_no"
            case cardId = "card_id"
            case bankNo = "bank_no"
            case expireDate = "expire_date"
            case cardType = "card_type"
            case cardBalance = "card_balance"
            case transBalance = "trans_balance"
            case lost
            case frozen
            case organizationName = "organization_name"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case jAccountAccount = "jaccount_account"
        case userName = "user_name"
        case userCode = "user_code"
        case cardCount = "card_count"
        case cards
    }
}

struct CampusCardTransactionsToolResult: Encodable {
    let ok: Bool = true
    let cardNo: String
    let startDate: String
    let endDate: String
    let unicodeIncluded: Bool
    let warnings: [String]?
    let itemCount: Int
    let expenseCount: Int
    let expenseAmount: Double
    let incomeCount: Int
    let incomeAmount: Double
    let items: [Item]

    struct Item: Encodable {
        let source: String
        let transactionAt: String
        let dateTimeMs: Int
        let system: String
        let merchantNo: String?
        let merchant: String
        let description: String
        let amount: Double
        let cardBalance: Double?

        enum CodingKeys: String, CodingKey {
            case source
            case transactionAt = "transaction_at"
            case dateTimeMs = "date_time_ms"
            case system
            case merchantNo = "merchant_no"
            case merchant
            case description
            case amount
            case cardBalance = "card_balance"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case cardNo = "card_no"
        case startDate = "start_date"
        case endDate = "end_date"
        case unicodeIncluded = "unicode_included"
        case warnings
        case itemCount = "item_count"
        case expenseCount = "expense_count"
        case expenseAmount = "expense_amount"
        case incomeCount = "income_count"
        case incomeAmount = "income_amount"
        case items
    }
}

struct CampusCardCostAnalyticsToolResult: Encodable {
    let ok: Bool = true
    let cardNo: String
    let startDate: String
    let endDate: String
    let unicodeIncluded: Bool
    let warnings: [String]?
    let expenseTransactionCount: Int
    let totalExpenseAmount: Double
    let campusCardExpenseAmount: Double
    let unicodeExpenseAmount: Double?
    let dailyCosts: [DailyCost]
    let monthlyCosts: [MonthlyCost]
    let categoryCosts: [CategoryCost]
    let hourlyCosts: [HourlyCost]
    let topMerchantsByCount: [MerchantCost]

    struct DailyCost: Encodable {
        let date: String
        let expenseAmount: Double
        let transactionCount: Int

        enum CodingKeys: String, CodingKey {
            case date
            case expenseAmount = "expense_amount"
            case transactionCount = "transaction_count"
        }
    }

    struct MonthlyCost: Encodable {
        let month: String
        let expenseAmount: Double
        let transactionCount: Int

        enum CodingKeys: String, CodingKey {
            case month
            case expenseAmount = "expense_amount"
            case transactionCount = "transaction_count"
        }
    }

    struct CategoryCost: Encodable {
        let type: String
        let expenseAmount: Double
        let transactionCount: Int

        enum CodingKeys: String, CodingKey {
            case type
            case expenseAmount = "expense_amount"
            case transactionCount = "transaction_count"
        }
    }

    struct HourlyCost: Encodable {
        let hour: Int
        let expenseAmount: Double
        let transactionCount: Int

        enum CodingKeys: String, CodingKey {
            case hour
            case expenseAmount = "expense_amount"
            case transactionCount = "transaction_count"
        }
    }

    struct MerchantCost: Encodable {
        let merchant: String
        let expenseAmount: Double
        let transactionCount: Int

        enum CodingKeys: String, CodingKey {
            case merchant
            case expenseAmount = "expense_amount"
            case transactionCount = "transaction_count"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case cardNo = "card_no"
        case startDate = "start_date"
        case endDate = "end_date"
        case unicodeIncluded = "unicode_included"
        case warnings
        case expenseTransactionCount = "expense_transaction_count"
        case totalExpenseAmount = "total_expense_amount"
        case campusCardExpenseAmount = "campus_card_expense_amount"
        case unicodeExpenseAmount = "unicode_expense_amount"
        case dailyCosts = "daily_costs"
        case monthlyCosts = "monthly_costs"
        case categoryCosts = "category_costs"
        case hourlyCosts = "hourly_costs"
        case topMerchantsByCount = "top_merchants_by_count"
    }
}

struct CanvasTodoItemsToolResult: Encodable {
    let ok: Bool = true
    let itemCount: Int
    let items: [Item]

    struct Item: Encodable {
        let assignmentId: String
        let assignmentName: String
        let courseName: String
        let dueAt: String?
        let dueText: String
        let pointsPossible: Double?
        let status: String
        let statusText: String
        let score: Double?

        enum CodingKeys: String, CodingKey {
            case assignmentId = "assignment_id"
            case assignmentName = "assignment_name"
            case courseName = "course_name"
            case dueAt = "due_at"
            case dueText = "due_text"
            case pointsPossible = "points_possible"
            case status
            case statusText = "status_text"
            case score
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case itemCount = "item_count"
        case items
    }
}

struct ToolNotificationItem: Encodable {
    let notificationId: String
    let title: String
    let content: String
    let scheduledAtBeijing: String
    let scheduledTimeMs: Int64

    enum CodingKeys: String, CodingKey {
        case notificationId = "notification_id"
        case title
        case content
        case scheduledAtBeijing = "scheduled_at_beijing"
        case scheduledTimeMs = "scheduled_time_ms"
    }
}

struct ScheduleNotificationToolResult: Encodable {
    let ok: Bool = true
    let notification: ToolNotificationItem
}

struct PendingNotificationsToolResult: Encodable {
    let ok: Bool = true
    let itemCount: Int
    let notifications: [ToolNotificationItem]

    enum CodingKeys: String, CodingKey {
        case ok
        case itemCount = "item_count"
        case notifications
    }
}

struct DeletePendingNotificationsToolResult: Encodable {
    let ok: Bool = true
    let deletedCount: Int
    let deletedNotifications: [ToolNotificationItem]

    enum CodingKeys: String, CodingKey {
        case ok
        case deletedCount = "deleted_count"
        case deletedNotifications = "deleted_notifications"
    }
}

struct CurrentDataSourceSemesterToolResult: Encodable {
    let ok: Bool = true
    let comparison: String
    let date: String
    let sourceName: String
    let entries: [Entry]

    struct Entry: Encodable {
        let sourceName: String
        let collegeID: Int
        let found: Bool
        let semester: SemesterInfo?

        enum CodingKeys: String, CodingKey {
            case sourceName = "source_name"
            case collegeID = "college_id"
            case found
            case semester
        }
    }

    struct SemesterInfo: Encodable {
        let id: String
        let name: String
        let startAt: String
        let endAt: String
        let totalWeeks: Int

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case startAt = "start_at"
            case endAt = "end_at"
            case totalWeeks = "total_weeks"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case comparison
        case date
        case sourceName = "source_name"
        case entries
    }
}

struct CurrentDataSourceSchedulesToolResult: Encodable {
    let ok: Bool = true
    let date: String
    let sourceName: String
    let items: [Item]

    struct Item: Encodable {
        let kind: String
        let sourceName: String
        let name: String
        let startTime: String
        let endTime: String
        let location: String?
        let teachers: [String]?

        enum CodingKeys: String, CodingKey {
            case kind
            case sourceName = "source_name"
            case name
            case startTime = "start_time"
            case endTime = "end_time"
            case location
            case teachers
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case date
        case sourceName = "source_name"
        case items
    }
}

struct SemesterExamArrangementsToolResult: Encodable {
    let ok: Bool = true
    let year: Int
    let semester: String
    let semesterName: String
    let examCount: Int
    let ongoingCount: Int
    let upcomingCount: Int
    let endedCount: Int
    let unscheduledCount: Int
    let items: [Item]

    struct Item: Encodable {
        let code: String
        let courseName: String
        let courseCode: String
        let classCode: String
        let examName: String
        let examType: String?
        let gradeType: String?
        let campus: String
        let location: String
        let startAt: String?
        let endAt: String?
        let status: String
        let statusText: String
        let isRebuild: Bool
        let order: Int

        enum CodingKeys: String, CodingKey {
            case code
            case courseName = "course_name"
            case courseCode = "course_code"
            case classCode = "class_code"
            case examName = "exam_name"
            case examType = "exam_type"
            case gradeType = "grade_type"
            case campus
            case location
            case startAt = "start_at"
            case endAt = "end_at"
            case status
            case statusText = "status_text"
            case isRebuild = "is_rebuild"
            case order
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case year
        case semester
        case semesterName = "semester_name"
        case examCount = "exam_count"
        case ongoingCount = "ongoing_count"
        case upcomingCount = "upcoming_count"
        case endedCount = "ended_count"
        case unscheduledCount = "unscheduled_count"
        case items
    }
}

struct SemesterGradesToolResult: Encodable {
    let ok: Bool = true
    let year: Int
    let semester: String
    let semesterName: String
    let gradeCount: Int
    let items: [Item]

    struct Item: Encodable {
        let id: String
        let courseName: String
        let courseCode: String
        let credit: String
        let score: String
        let grade: String?
        let remark: String?
        let teacher: String
        let displayValue: String
        let secondaryValue: String?

        enum CodingKeys: String, CodingKey {
            case id
            case courseName = "course_name"
            case courseCode = "course_code"
            case credit
            case score
            case grade
            case remark
            case teacher
            case displayValue = "display_value"
            case secondaryValue = "secondary_value"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case year
        case semester
        case semesterName = "semester_name"
        case gradeCount = "grade_count"
        case items
    }
}

struct GPAStatisticsToolResult: Encodable {
    let ok: Bool = true
    let rangeDescription: String
    let startYear: Int?
    let startSemester: String?
    let endYear: Int?
    let endSemester: String?
    let found: Bool
    let item: Item?

    struct Item: Encodable {
        let className: String
        let failedCourseCount: Int?
        let failedCredits: String
        let gpa: String
        let gpaRank: String
        let gpaRankPosition: Int?
        let totalStudents: Int?
        let earnedCredits: String
        let academicPoints: String
        let academicPointsRank: String
        let academicPointsRankPosition: Int?
        let totalCredits: String
        let courseScope: String?
        let collegeName: String?
        let majorName: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case className = "class_name"
            case failedCourseCount = "failed_course_count"
            case failedCredits = "failed_credits"
            case gpa
            case gpaRank = "gpa_rank"
            case gpaRankPosition = "gpa_rank_position"
            case totalStudents = "total_students"
            case earnedCredits = "earned_credits"
            case academicPoints = "academic_points"
            case academicPointsRank = "academic_points_rank"
            case academicPointsRankPosition = "academic_points_rank_position"
            case totalCredits = "total_credits"
            case courseScope = "course_scope"
            case collegeName = "college_name"
            case majorName = "major_name"
            case updatedAt = "updated_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case rangeDescription = "range_description"
        case startYear = "start_year"
        case startSemester = "start_semester"
        case endYear = "end_year"
        case endSemester = "end_semester"
        case found
        case item
    }
}

struct SelfStudyToolSectionInfo: Encodable {
    let sectionIndex: Int
    let startTime: String
    let endTime: String

    enum CodingKeys: String, CodingKey {
        case sectionIndex = "section_index"
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

struct SelfStudyToolCourseInfo: Encodable {
    let name: String
    let teacherName: String?
    let startSection: Int
    let endSection: Int

    enum CodingKeys: String, CodingKey {
        case name
        case teacherName = "teacher_name"
        case startSection = "start_section"
        case endSection = "end_section"
    }
}

struct SelfStudyBuildingRoomsToolResult: Encodable {
    let ok: Bool = true
    let campusName: String
    let buildingName: String
    let referenceSection: SelfStudyToolSectionInfo?
    let roomCount: Int
    let availableRoomCount: Int
    let rooms: [Room]

    struct Room: Encodable {
        let id: Int
        let name: String
        let floorName: String
        let currentStudentCount: Int?
        let status: String
        let currentCourse: SelfStudyToolCourseInfo?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case floorName = "floor_name"
            case currentStudentCount = "current_student_count"
            case status
            case currentCourse = "current_course"
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case campusName = "campus_name"
        case buildingName = "building_name"
        case referenceSection = "reference_section"
        case roomCount = "room_count"
        case availableRoomCount = "available_room_count"
        case rooms
    }
}

struct SelfStudyRoomRealtimeStatusToolResult: Encodable {
    let ok: Bool = true
    let roomId: Int
    let roomName: String
    let campusName: String
    let buildingName: String
    let floorName: String
    let status: String
    let currentStudentCount: Int?
    let referenceSection: SelfStudyToolSectionInfo?
    let currentCourse: SelfStudyToolCourseInfo?
    let hasEnvironmentSensor: Bool
    let environmentMetrics: [EnvironmentMetric]
    let hasPanorama: Bool
    let facilities: [Facility]
    let sectionDetails: [SectionDetail]
    let todayCourses: [SelfStudyToolCourseInfo]
    let warnings: [String]?

    struct EnvironmentMetric: Encodable {
        let key: String
        let title: String
        let value: String
        let displayOrder: Int

        enum CodingKeys: String, CodingKey {
            case key
            case title
            case value
        }
    }

    struct Facility: Encodable {
        let name: String
        let value: String
    }

    struct SectionDetail: Encodable {
        let sectionIndex: Int
        let startTime: String
        let endTime: String
        let status: String
        let course: SelfStudyToolCourseInfo?

        enum CodingKeys: String, CodingKey {
            case sectionIndex = "section_index"
            case startTime = "start_time"
            case endTime = "end_time"
            case status
            case course
        }
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case roomId = "room_id"
        case roomName = "room_name"
        case campusName = "campus_name"
        case buildingName = "building_name"
        case floorName = "floor_name"
        case status
        case currentStudentCount = "current_student_count"
        case referenceSection = "reference_section"
        case currentCourse = "current_course"
        case hasEnvironmentSensor = "has_environment_sensor"
        case environmentMetrics = "environment_metrics"
        case hasPanorama = "has_panorama"
        case facilities
        case sectionDetails = "section_details"
        case todayCourses = "today_courses"
        case warnings
    }
}

struct ToolExecutionErrorResult: Encodable {
    let ok: Bool = false
    let error: String
}
