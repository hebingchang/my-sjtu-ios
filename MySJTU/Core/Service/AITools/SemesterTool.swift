//
//  SemesterTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class CurrentDataSourceSemesterToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_semester_information",
                displayName: "获取学期信息",
                category: .query,
                functionDescription: "获取 app 当前数据源相对于给定日期的学期信息。",
                parametersSchema: .currentDataSourceSemester,
                isAvailableInChat: true
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            do {
                let argumentsData = Data(argumentsJSON.utf8)
                let arguments = try JSONDecoder().decode(CurrentDataSourceSemesterToolArguments.self, from: argumentsData)

                guard let comparison = SemesterDateComparison.parse(arguments.comparison) else {
                    return AIService.encodeToolExecutionError(
                        .init(error: "comparison 参数无效，必须是“早于”、“等于”或“晚于”。")
                    )
                }

                guard let date = AIService.parseToolDate(arguments.date) else {
                    return AIService.encodeToolExecutionError(
                        .init(error: "date 参数无效，必须是 YYYY-MM-DD 或 ISO-8601 日期。")
                    )
                }

                let snapshot = AcademicContextService.semesterLookup(
                    comparison: comparison,
                    date: date
                )

                guard snapshot.databaseAvailable else {
                    return AIService.encodeToolExecutionError(
                        .init(error: "当前无法读取学期数据库。")
                    )
                }

                let result = CurrentDataSourceSemesterToolResult(
                    comparison: comparison.displayName,
                    date: date.formattedDate(),
                    sourceName: snapshot.sourceName,
                    entries: snapshot.entries.map { entry in
                        CurrentDataSourceSemesterToolResult.Entry(
                            sourceName: entry.sourceName,
                            collegeID: entry.college.rawValue,
                            found: entry.semester != nil,
                            semester: entry.semester.map {
                                CurrentDataSourceSemesterToolResult.SemesterInfo(
                                    id: $0.id,
                                    name: AcademicContextService.semesterDisplayTitle(for: $0),
                                    startAt: $0.start_at.formattedDate(),
                                    endAt: max($0.start_at, $0.end_at.addSeconds(-1)).formattedDate(),
                                    totalWeeks: $0.displayWeekCount()
                                )
                            }
                        )
                    }
                )

                return AIService.encodeToolExecutionResult(result)
            } catch {
                return AIService.encodeToolExecutionError(
                    .init(error: "工具参数解析失败：\(error.localizedDescription)")
                )
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            guard let parsed = parsedInvocation(argumentsJSON: argumentsJSON) else {
                return await super.invocationStatusPayload(argumentsJSON: argumentsJSON)
            }

            let snapshot = AcademicContextService.semesterLookup(
                comparison: parsed.comparison,
                date: parsed.date
            )
            let semesterNames = AIService.orderedUniqueSemesterNames(from: snapshot)

            let text: String
            if semesterNames.count == 1, let semesterName = semesterNames.first {
                text = "已调用“获取\(semesterName)信息”"
            } else if !semesterNames.isEmpty {
                text = "已调用“获取\(semesterNames.joined(separator: "、"))信息”"
            } else {
                let monthDay = AIService.formattedToolStatusDate(parsed.date)
                switch parsed.comparison {
                case .equal:
                    text = "已调用“获取\(monthDay)所在学期信息”"
                case .earlier:
                    text = "已调用“获取\(monthDay)之前的学期信息”"
                case .later:
                    text = "已调用“获取\(monthDay)之后的学期信息”"
                }
            }

            return .init(
                text: text,
                functionName: functionName,
                category: category,
                invocationKey: "\(functionName)|comparison=\(parsed.comparison.rawValue)|date=\(parsed.date.formattedDate())"
            )
        }

        private func parsedInvocation(
            argumentsJSON: String
        ) -> (comparison: SemesterDateComparison, date: Date)? {
            guard let argumentsData = argumentsJSON.data(using: .utf8),
                  let arguments = try? JSONDecoder().decode(
                      CurrentDataSourceSemesterToolArguments.self,
                      from: argumentsData
                  ),
                  let comparison = SemesterDateComparison.parse(arguments.comparison),
                  let date = AIService.parseToolDate(arguments.date) else {
                return nil
            }

            return (comparison, date)
        }
    }
}
