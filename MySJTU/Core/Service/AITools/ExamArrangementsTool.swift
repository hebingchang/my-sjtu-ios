//
//  ExamArrangementsTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class SemesterExamArrangementsToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_exam_arrangements",
                displayName: "查询考试安排",
                category: .query,
                functionDescription: "查询指定学期的考试安排信息。调用前会检查当前 jAccount 是否已启用考试与成绩功能；若未启用，则直接返回提示用户前往账户页启用考试与成绩功能。",
                parametersSchema: .academicYearSemester,
                isAvailableInChat: true
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            do {
                let argumentsData = Data(argumentsJSON.utf8)
                let arguments = try JSONDecoder().decode(AcademicYearSemesterToolArguments.self, from: argumentsData)

                guard let semester = ExamAndGradeSemesterSelection.parse(arguments.semester) else {
                    return AIService.encodeToolExecutionError(
                        .init(error: "semester 参数无效，必须是“秋”、“春”或“夏”。")
                    )
                }

                guard let account = AIService.enabledExamAndGradeAccount() else {
                    return AIService.encodeToolExecutionError(
                        .init(error: AIService.examAndGradeUnavailableErrorText())
                    )
                }

                let result = try await AIService.fetchSemesterExamArrangementsResult(
                    account: account,
                    year: arguments.year,
                    semester: semester
                )
                return AIService.encodeToolExecutionResult(result)
            } catch {
                if error is DecodingError {
                    return AIService.encodeToolExecutionError(
                        .init(error: "工具参数解析失败：\(error.localizedDescription)")
                    )
                }

                return AIService.encodeToolExecutionError(
                    .init(error: AIService.examAndGradeToolErrorText(error, subject: "考试安排"))
                )
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            guard let parsed = parsedInvocation(argumentsJSON: argumentsJSON) else {
                return await super.invocationStatusPayload(argumentsJSON: argumentsJSON)
            }

            let semesterName = AIService.examAndGradeSemesterDisplayName(
                year: parsed.year,
                semester: parsed.semester
            )

            return .init(
                text: "已调用“查询\(semesterName)考试安排”",
                functionName: functionName,
                category: category,
                invocationKey: "\(functionName)|year=\(parsed.year)|semester=\(parsed.semester.displayName)"
            )
        }

        private func parsedInvocation(
            argumentsJSON: String
        ) -> (year: Int, semester: ExamAndGradeSemesterSelection)? {
            guard let argumentsData = argumentsJSON.data(using: .utf8),
                  let arguments = try? JSONDecoder().decode(
                      AcademicYearSemesterToolArguments.self,
                      from: argumentsData
                  ),
                  let semester = ExamAndGradeSemesterSelection.parse(arguments.semester) else {
                return nil
            }

            return (arguments.year, semester)
        }
    }
}
