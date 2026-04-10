//
//  ToolSupport.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation
import Apollo

extension AIService {
    typealias CanvasAssignment = CanvasSchema.GetAssignmentQuery.Data.Assignment
    typealias CanvasSubmissionNode = CanvasSchema.GetAssignmentQuery.Data.Assignment.SubmissionsConnection.Node

    enum CanvasAuthorizationState {
        case notEnabled
        case missingToken
        case ready(token: String)
    }

    struct CanvasTodoStatusInfo {
        let code: String
        let text: String
        let score: Double?
    }

    static func executeToolCall(
        _ toolCall: ChatCompletionResponse.ToolCall,
        toolNavigationHandler: ToolNavigationHandler?
    ) async -> String {
        guard let tool = ToolRegistry.tool(for: toolCall.function.name) else {
            return encodeToolExecutionError(
                .init(error: "未知工具：\(toolCall.function.name)")
            )
        }

        return await tool.execute(
            argumentsJSON: toolCall.function.arguments,
            toolNavigationHandler: toolNavigationHandler
        )
    }

    static func selfStudyClassroomErrorText(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .sessionExpired, .noAccount:
                return "服务暂时不可用，请稍后重试。"
            case .remoteError(let message), .runtimeError(let message):
                return message
            case .internalError:
                return "内部错误，请稍后重试。"
            }
        }

        return error.localizedDescription
    }

    static func selfStudyToolSectionInfo(
        from section: SelfStudyClassroomAPI.SectionTime?
    ) -> SelfStudyToolSectionInfo? {
        guard let section else {
            return nil
        }

        return .init(
            sectionIndex: section.sectionIndex,
            startTime: section.startTime,
            endTime: section.endTime
        )
    }

    static func selfStudyToolCourseInfo(
        from course: SelfStudyClassroomAPI.RoomCourse
    ) -> SelfStudyToolCourseInfo {
        .init(
            name: course.courseName,
            teacherName: course.teacherName,
            startSection: course.startSection,
            endSection: course.endSection
        )
    }

    static func selfStudyEnvironmentMetrics(
        from environment: SelfStudyClassroomAPI.RoomEnvironmental
    ) -> [SelfStudyRoomRealtimeStatusToolResult.EnvironmentMetric] {
        environment.sensorValues.map { key, value in
            let normalizedKey = key.lowercased()
            let config = selfStudyEnvironmentConfig(for: normalizedKey)

            return SelfStudyRoomRealtimeStatusToolResult.EnvironmentMetric(
                key: normalizedKey,
                title: config.title,
                value: formattedSelfStudyEnvironmentValue(
                    rawValue: value,
                    key: normalizedKey,
                    unit: config.unit
                ),
                displayOrder: config.order
            )
        }
        .sorted { lhs, rhs in
            if lhs.displayOrder != rhs.displayOrder {
                return lhs.displayOrder < rhs.displayOrder
            }
            return lhs.title < rhs.title
        }
    }

    static func selfStudyEnvironmentConfig(
        for key: String
    ) -> (title: String, unit: String?, order: Int) {
        switch key {
        case "temp":
            return ("温度", "℃", 0)
        case "hum":
            return ("湿度", "%", 1)
        case "pm":
            return ("PM2.5", "μg/m³", 2)
        case "co":
            return ("CO₂", "ppm", 3)
        case "lux":
            return ("照度", "lx", 4)
        case "tvoc":
            return ("TVOC", "mg/m³", 5)
        default:
            return (key.uppercased(), nil, 100)
        }
    }

    static func formattedSelfStudyEnvironmentValue(
        rawValue: String,
        key: String,
        unit: String?
    ) -> String {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Double(trimmedValue) else {
            return unit.map { "\(trimmedValue) \($0)" } ?? trimmedValue
        }

        let formattedNumber: String = {
            switch key {
            case "temp", "hum":
                return number.formatted(.number.precision(.fractionLength(0...1)))
            case "tvoc":
                return number.formatted(.number.precision(.fractionLength(0...3)))
            default:
                return number.formatted(.number.precision(.fractionLength(0...2)))
            }
        }()

        return unit.map { "\(formattedNumber) \($0)" } ?? formattedNumber
    }

    static func canvasAuthorizationState(
        userDefaults: UserDefaults = .standard
    ) -> CanvasAuthorizationState {
        let accounts = storedAccounts(userDefaults: userDefaults)

        guard let jAccount = accounts.first(where: { $0.provider == .jaccount }),
              jAccount.enabledFeatures.contains(.canvas) else {
            return .notEnabled
        }

        guard let token = jAccount.bizData["canvas_token"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return .missingToken
        }

        return .ready(token: token)
    }

    static func storedAccounts(
        userDefaults: UserDefaults = .standard
    ) -> [WebAuthAccount] {
        guard let rawAccounts = userDefaults.string(forKey: "accounts"),
              let accounts = [WebAuthAccount](rawValue: rawAccounts) else {
            return []
        }

        return accounts
    }

    static func fetchCanvasTodoItems(
        token: String
    ) async throws -> [CanvasTodoItemsToolResult.Item] {
        let api = CanvasAPI(token: token)
        let events = try await api.getUpcomingEvents()
        let assignmentIDs = events.compactMap { $0.assignment?.id }

        guard !assignmentIDs.isEmpty else {
            return []
        }

        let assignments = try await api.getAssignments(assignmentIds: assignmentIDs)
        return makeCanvasTodoItems(from: assignments)
    }

    static func makeCanvasTodoItems(
        from assignments: [CanvasAssignment]
    ) -> [CanvasTodoItemsToolResult.Item] {
        assignments
            .sorted(by: sortCanvasAssignments)
            .map { assignment in
                let dueDate = assignment.dueAt.flatMap { CanvasFormatters.iso8601.date(from: $0) }
                let latestSubmission = latestCanvasSubmission(for: assignment)
                let status = canvasTodoStatus(
                    for: assignment,
                    dueDate: dueDate,
                    latestSubmission: latestSubmission
                )

                return CanvasTodoItemsToolResult.Item(
                    assignmentId: assignment.id,
                    assignmentName: sanitizedCanvasTodoName(assignment.name),
                    courseName: sanitizedCanvasTodoName(
                        assignment.course?.name,
                        fallback: "未命名课程"
                    ),
                    dueAt: assignment.dueAt,
                    dueText: canvasTodoDueText(dueDate: dueDate, statusCode: status.code),
                    pointsPossible: assignment.pointsPossible,
                    status: status.code,
                    statusText: status.text,
                    score: status.score
                )
            }
    }

    static func sortCanvasAssignments(
        _ lhs: CanvasAssignment,
        _ rhs: CanvasAssignment
    ) -> Bool {
        let lhsDueDate = lhs.dueAt.flatMap { CanvasFormatters.iso8601.date(from: $0) }
        let rhsDueDate = rhs.dueAt.flatMap { CanvasFormatters.iso8601.date(from: $0) }
        let lhsCourseName = sanitizedCanvasTodoName(lhs.course?.name, fallback: "未命名课程")
        let rhsCourseName = sanitizedCanvasTodoName(rhs.course?.name, fallback: "未命名课程")
        let lhsAssignmentName = sanitizedCanvasTodoName(lhs.name)
        let rhsAssignmentName = sanitizedCanvasTodoName(rhs.name)

        return canvasCompareDates(
            lhsDueDate,
            rhsDueDate,
            order: .ascending,
            fallback: {
                let courseComparison = lhsCourseName.localizedStandardCompare(rhsCourseName)
                if courseComparison != .orderedSame {
                    return courseComparison == .orderedAscending
                }

                return lhsAssignmentName.localizedStandardCompare(rhsAssignmentName) == .orderedAscending
            }()
        )
    }

    static func latestCanvasSubmission(
        for assignment: CanvasAssignment
    ) -> CanvasSubmissionNode? {
        guard let nodes = assignment.submissionsConnection?.nodes else {
            return nil
        }

        return nodes
            .compactMap { $0 }
            .max(by: { $0.attempt < $1.attempt })
    }

    static func canvasTodoStatus(
        for assignment: CanvasAssignment,
        dueDate: Date?,
        latestSubmission: CanvasSubmissionNode?
    ) -> CanvasTodoStatusInfo {
        if let latestSubmission,
           latestSubmission.gradingStatus == .graded {
            return .init(
                code: "graded",
                text: "已评分",
                score: latestSubmission.score
            )
        }

        if latestSubmission != nil {
            return .init(
                code: "submitted",
                text: "已提交",
                score: nil
            )
        }

        if let dueDate,
           dueDate < .now {
            return .init(
                code: "overdue",
                text: "已逾期",
                score: nil
            )
        }

        if dueDate == nil {
            return .init(
                code: "unscheduled",
                text: "待查看",
                score: nil
            )
        }

        return .init(
            code: "upcoming",
            text: "待完成",
            score: nil
        )
    }

    static func sanitizedCanvasTodoName(
        _ value: String?,
        fallback: String = "未命名待办事项"
    ) -> String {
        let sanitized = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? fallback : sanitized
    }

    static func canvasTodoDueText(
        dueDate: Date?,
        statusCode: String
    ) -> String {
        guard let dueDate else {
            return "未设置截止时间"
        }

        if statusCode == "overdue" {
            return dueDate.formattedCanvasRelativeDueDate(includeOverduePrefix: true)
        }

        return dueDate.formattedCanvasRelativeDueDate()
    }

    static func canvasTodoErrorText(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .sessionExpired:
                return "Canvas 令牌可能已失效，请在账户设置中重新启用。"
            case .noAccount:
                return "当前 jAccount 尚未打开 Canvas 功能，请先在账户页中授权打开。"
            case .remoteError(let message), .runtimeError(let message):
                return message
            case .internalError:
                return "无法加载待办事项列表，请稍后重试。"
            }
        }

        if let responseCodeError = error as? ResponseCodeInterceptor.ResponseCodeError {
            if case .invalidResponseCode = responseCodeError {
                return "Canvas 令牌可能已失效，请在账户设置中重新启用。"
            }
        }

        return "无法加载待办事项列表，请稍后重试。"
    }

    static func parseToolDate(_ rawValue: String) -> Date? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if let date = Date.fromFormat("yyyy-MM-dd", dateStr: trimmedValue) {
            return date.startOfDay()
        }

        if let date = Date.fromFormat("yyyy/MM/dd", dateStr: trimmedValue) {
            return date.startOfDay()
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmedValue) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmedValue)
    }

    static func encodeToolExecutionResult<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"ok":false,"error":"工具返回结果编码失败。"}"#
        }
        return string
    }

    static func encodeToolExecutionError(_ value: ToolExecutionErrorResult) -> String {
        encodeToolExecutionResult(value)
    }

    static func toolInvocationStatusPayload(
        for toolCall: ChatCompletionResponse.ToolCall
    ) async -> ToolStatusPayload {
        if let tool = ToolRegistry.tool(for: toolCall.function.name) {
            return await tool.invocationStatusPayload(argumentsJSON: toolCall.function.arguments)
        }

        return .init(
            text: "已调用“\(toolCall.function.name)”",
            functionName: toolCall.function.name,
            category: toolCategory(for: toolCall.function.name),
            invocationKey: genericToolInvocationKey(for: toolCall)
        )
    }

    static func toolPermissionDeniedStatusPayload(
        for toolCall: ChatCompletionResponse.ToolCall,
        toolDisplayName: String
    ) -> ToolStatusPayload {
        .init(
            text: "用户拒绝了「\(toolDisplayName)」",
            functionName: toolCall.function.name,
            category: toolCategory(for: toolCall.function.name),
            invocationKey: genericToolInvocationKey(for: toolCall)
        )
    }

    static func formattedToolStatusDate(_ date: Date) -> String {
        date.formatted(format: "M月d日")
    }

    static func orderedUniqueSemesterNames(
        from snapshot: AcademicSemesterLookupSnapshot
    ) -> [String] {
        var names: [String] = []

        for entry in snapshot.entries {
            guard let semester = entry.semester else {
                continue
            }

            let title = AcademicContextService.semesterDisplayTitle(for: semester)
            if !names.contains(title) {
                names.append(title)
            }
        }

        return names
    }

    static func genericToolInvocationKey(
        functionName: String,
        argumentsJSON: String
    ) -> String {
        let trimmedArguments = argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArguments.isEmpty else {
            return functionName
        }

        return "\(functionName)|\(trimmedArguments)"
    }

    static func genericToolInvocationKey(
        for toolCall: ChatCompletionResponse.ToolCall
    ) -> String {
        genericToolInvocationKey(
            functionName: toolCall.function.name,
            argumentsJSON: toolCall.function.arguments
        )
    }

    static func encodeToolStatusPayload(_ payload: ToolStatusPayload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(payload),
              let string = String(data: data, encoding: .utf8) else {
            return payload.text
        }

        return string
    }

    static func appendToolStatus(_ status: ToolStatusPayload, to current: String) -> String {
        current + "\(toolStatusOpeningTag)\(encodeToolStatusPayload(status))\(toolStatusClosingTag)"
    }
}
