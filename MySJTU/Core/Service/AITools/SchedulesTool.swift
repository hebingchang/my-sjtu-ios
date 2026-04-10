//
//  SchedulesTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class CurrentDataSourceSchedulesToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_schedules",
                displayName: "获取日程信息",
                category: .query,
                functionDescription: "获取 app 当前数据源在给定日期中的全部日程信息，包括课程和自定义日程。",
                parametersSchema: .currentDataSourceSchedules,
                isAvailableInChat: true
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            do {
                let argumentsData = Data(argumentsJSON.utf8)
                let arguments = try JSONDecoder().decode(CurrentDataSourceSchedulesToolArguments.self, from: argumentsData)

                guard let date = AIService.parseToolDate(arguments.date) else {
                    return AIService.encodeToolExecutionError(
                        .init(error: "date 参数无效，必须是 YYYY-MM-DD 或 ISO-8601 日期。")
                    )
                }

                let snapshot = AcademicContextService.dateScheduleLookup(date: date)

                guard snapshot.databaseAvailable else {
                    return AIService.encodeToolExecutionError(
                        .init(error: "当前无法读取日程数据库。")
                    )
                }

                let result = CurrentDataSourceSchedulesToolResult(
                    date: snapshot.requestedDate.formattedDate(),
                    sourceName: snapshot.sourceName,
                    items: snapshot.items.map { item in
                        CurrentDataSourceSchedulesToolResult.Item(
                            kind: item.kind.displayName,
                            sourceName: item.sourceName,
                            name: item.name,
                            startTime: item.startAt.formatted(format: "H:mm"),
                            endTime: item.endAt.formatted(format: "H:mm"),
                            location: item.location,
                            teachers: item.teachers.isEmpty ? nil : item.teachers
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
            guard let date = parsedDate(argumentsJSON: argumentsJSON) else {
                return await super.invocationStatusPayload(argumentsJSON: argumentsJSON)
            }

            return .init(
                text: "已调用“获取\(AIService.formattedToolStatusDate(date))的日程信息”",
                functionName: functionName,
                category: category,
                invocationKey: "\(functionName)|date=\(date.formattedDate())"
            )
        }

        private func parsedDate(argumentsJSON: String) -> Date? {
            guard let argumentsData = argumentsJSON.data(using: .utf8),
                  let arguments = try? JSONDecoder().decode(
                      CurrentDataSourceSchedulesToolArguments.self,
                      from: argumentsData
                  ) else {
                return nil
            }

            return AIService.parseToolDate(arguments.date)
        }
    }
}
