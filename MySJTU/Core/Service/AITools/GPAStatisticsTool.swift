//
//  GPAStatisticsTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class GPAStatisticsToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_gpa_statistics",
                displayName: "查询GPA与学积分",
                category: .query,
                functionDescription: "查询指定学期范围内的 GPA（绩点）、学积分、获得学分与对应排名。支持四种模式：1. 省略全部范围参数，统计全部学期；2. 只提供 start_year 和 start_semester，统计从该学期开始的全部学期；3. 只提供 end_year 和 end_semester，统计截至该学期（含）的全部学期；4. 同时提供开始与结束学期，统计闭区间内的学期。每个边界都必须成对提供 year 和 semester。调用前会检查当前 jAccount 是否已启用考试与成绩功能；若未启用，则直接返回提示用户前往账户页启用考试与成绩功能。",
                parametersSchema: .examAndGradeStatisticsRange,
                isAvailableInChat: true
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            do {
                let argumentsData = Data(argumentsJSON.utf8)
                let arguments = try JSONDecoder().decode(
                    ExamAndGradeStatisticsRangeToolArguments.self,
                    from: argumentsData
                )
                let range = try parsedRange(from: arguments)

                guard let account = AIService.enabledExamAndGradeAccount() else {
                    return AIService.encodeToolExecutionError(
                        .init(error: AIService.examAndGradeUnavailableErrorText())
                    )
                }

                let result = try await AIService.fetchGPAStatisticsResult(
                    account: account,
                    startYear: range.startYear,
                    startSemester: range.startSemester,
                    endYear: range.endYear,
                    endSemester: range.endSemester
                )
                return AIService.encodeToolExecutionResult(result)
            } catch {
                if error is DecodingError {
                    return AIService.encodeToolExecutionError(
                        .init(error: "工具参数解析失败：\(error.localizedDescription)")
                    )
                }

                return AIService.encodeToolExecutionError(
                    .init(error: AIService.examAndGradeToolErrorText(error, subject: "GPA 与学积分"))
                )
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            guard let parsed = parsedInvocation(argumentsJSON: argumentsJSON) else {
                return await super.invocationStatusPayload(argumentsJSON: argumentsJSON)
            }

            let rangeDescription = AIService.examAndGradeStatisticsRangeDescription(
                startYear: parsed.startYear,
                startSemester: parsed.startSemester,
                endYear: parsed.endYear,
                endSemester: parsed.endSemester
            )

            return .init(
                text: "已调用“查询\(rangeDescription) GPA 与学积分”",
                functionName: functionName,
                category: category,
                invocationKey: invocationKey(for: parsed)
            )
        }

        private func parsedInvocation(
            argumentsJSON: String
        ) -> (
            startYear: Int?,
            startSemester: ExamAndGradeSemesterSelection?,
            endYear: Int?,
            endSemester: ExamAndGradeSemesterSelection?
        )? {
            guard let argumentsData = argumentsJSON.data(using: .utf8),
                  let arguments = try? JSONDecoder().decode(
                      ExamAndGradeStatisticsRangeToolArguments.self,
                      from: argumentsData
                  ),
                  let range = try? parsedRange(from: arguments) else {
                return nil
            }

            return range
        }

        private func parsedRange(
            from arguments: ExamAndGradeStatisticsRangeToolArguments
        ) throws -> (
            startYear: Int?,
            startSemester: ExamAndGradeSemesterSelection?,
            endYear: Int?,
            endSemester: ExamAndGradeSemesterSelection?
        ) {
            let fields: [Any?] = [
                arguments.startYear,
                arguments.startSemester,
                arguments.endYear,
                arguments.endSemester
            ]
            let containsAnyRangeField = fields.contains { $0 != nil }

            guard containsAnyRangeField else {
                return (nil, nil, nil, nil)
            }

            let hasStartBoundary = arguments.startYear != nil || arguments.startSemester != nil
            let hasEndBoundary = arguments.endYear != nil || arguments.endSemester != nil

            let startYear: Int?
            let startSemester: ExamAndGradeSemesterSelection?
            if hasStartBoundary {
                guard let parsedStartYear = arguments.startYear,
                      let startSemesterRaw = arguments.startSemester else {
                    throw APIError.runtimeError(
                        "start_year 和 start_semester 必须同时提供或同时留空。"
                    )
                }
                guard let parsedStartSemester = ExamAndGradeSemesterSelection.parse(startSemesterRaw) else {
                    throw APIError.runtimeError("start_semester 参数无效，必须是“秋”、“春”或“夏”。")
                }

                startYear = parsedStartYear
                startSemester = parsedStartSemester
            } else {
                startYear = nil
                startSemester = nil
            }

            let endYear: Int?
            let endSemester: ExamAndGradeSemesterSelection?
            if hasEndBoundary {
                guard let parsedEndYear = arguments.endYear,
                      let endSemesterRaw = arguments.endSemester else {
                    throw APIError.runtimeError(
                        "end_year 和 end_semester 必须同时提供或同时留空。"
                    )
                }
                guard let parsedEndSemester = ExamAndGradeSemesterSelection.parse(endSemesterRaw) else {
                    throw APIError.runtimeError("end_semester 参数无效，必须是“秋”、“春”或“夏”。")
                }

                endYear = parsedEndYear
                endSemester = parsedEndSemester
            } else {
                endYear = nil
                endSemester = nil
            }

            if let startYear,
               let startSemester,
               let endYear,
               let endSemester {
                let startSortKey = startYear * 10 + startSemester.code
                let endSortKey = endYear * 10 + endSemester.code
                guard startSortKey <= endSortKey else {
                    throw APIError.runtimeError("统计开始学期不能晚于结束学期。")
                }
            }

            return (startYear, startSemester, endYear, endSemester)
        }

        private func invocationKey(
            for range: (
                startYear: Int?,
                startSemester: ExamAndGradeSemesterSelection?,
                endYear: Int?,
                endSemester: ExamAndGradeSemesterSelection?
            )
        ) -> String {
            if range.startYear == nil,
               range.startSemester == nil,
               range.endYear == nil,
               range.endSemester == nil {
                return "\(functionName)|all"
            }

            let startPart = if let startYear = range.startYear,
                              let startSemester = range.startSemester {
                "start=\(startYear)-\(startSemester.displayName)"
            } else {
                "start=none"
            }
            let endPart = if let endYear = range.endYear,
                            let endSemester = range.endSemester {
                "end=\(endYear)-\(endSemester.displayName)"
            } else {
                "end=none"
            }

            return "\(functionName)|\(startPart)|\(endPart)"
        }
    }
}
