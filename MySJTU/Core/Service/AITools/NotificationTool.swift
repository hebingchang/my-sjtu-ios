//
//  NotificationTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class ScheduleNotificationToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "schedule_notification",
                displayName: "创建定时提醒",
                category: .notification,
                functionDescription: "按照北京时间创建一条本地推送通知。参数包括年、月、日、小时、分钟和推送内容；通知标题固定为“定时提醒”。调用前会检查并请求通知权限；如果没有权限，则直接返回“没有推送通知权限”。",
                parametersSchema: .scheduleNotification,
                isAvailableInChat: true,
                requiresUserAuthorization: false
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            do {
                let arguments = try JSONDecoder().decode(
                    ScheduleNotificationToolArguments.self,
                    from: Data(argumentsJSON.utf8)
                )

                let record = try await ToolNotificationService.shared.scheduleNotification(
                    year: arguments.year,
                    month: arguments.month,
                    day: arguments.day,
                    hour: arguments.hour,
                    minute: arguments.minute,
                    body: arguments.content
                )

                return AIService.encodeToolExecutionResult(
                    ScheduleNotificationToolResult(
                        notification: makeNotificationItem(from: record)
                    )
                )
            } catch let error as ToolNotificationServiceError {
                return AIService.encodeToolExecutionError(
                    .init(error: error.localizedDescription)
                )
            } catch {
                return AIService.encodeToolExecutionError(
                    .init(error: "工具参数解析失败：\(error.localizedDescription)")
                )
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            guard let arguments = parseArguments(argumentsJSON: argumentsJSON) else {
                return await super.invocationStatusPayload(argumentsJSON: argumentsJSON)
            }

            let timeText = String(
                format: "%d月%d日 %02d:%02d",
                arguments.month,
                arguments.day,
                arguments.hour,
                arguments.minute
            )

            return .init(
                text: "已调用“创建\(timeText)的定时提醒”",
                functionName: functionName,
                category: category,
                invocationKey: "\(functionName)|\(arguments.year)-\(arguments.month)-\(arguments.day) \(arguments.hour):\(arguments.minute)|\(arguments.content)"
            )
        }

        private func parseArguments(
            argumentsJSON: String
        ) -> ScheduleNotificationToolArguments? {
            try? JSONDecoder().decode(
                ScheduleNotificationToolArguments.self,
                from: Data(argumentsJSON.utf8)
            )
        }
    }

    final class PendingNotificationsToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_pending_notifications",
                displayName: "查询未触发通知",
                category: .notification,
                functionDescription: "查询当前由通知工具创建、且尚未触发的本地推送通知列表。",
                parametersSchema: .emptyObject,
                isAvailableInChat: true,
                requiresUserAuthorization: false
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            let notifications = await ToolNotificationService.shared.pendingNotifications()
            return AIService.encodeToolExecutionResult(
                PendingNotificationsToolResult(
                    itemCount: notifications.count,
                    notifications: notifications.map(makeNotificationItem)
                )
            )
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            .init(
                text: "已调用“查询未触发通知”",
                functionName: functionName,
                category: category,
                invocationKey: functionName
            )
        }
    }

    final class DeletePendingNotificationsToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "delete_pending_notifications",
                displayName: "删除未触发通知",
                category: .notification,
                functionDescription: "删除当前尚未触发的本地推送通知。可以传入 notification_id 删除某一条；如果省略 notification_id，则删除全部尚未触发的通知。",
                parametersSchema: .deletePendingNotifications,
                isAvailableInChat: true,
                requiresUserAuthorization: false
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            do {
                let arguments = try JSONDecoder().decode(
                    DeletePendingNotificationsToolArguments.self,
                    from: Data(argumentsJSON.utf8)
                )
                let deletedNotifications = await ToolNotificationService.shared.deletePendingNotifications(
                    notificationID: arguments.notificationId
                )

                return AIService.encodeToolExecutionResult(
                    DeletePendingNotificationsToolResult(
                        deletedCount: deletedNotifications.count,
                        deletedNotifications: deletedNotifications.map(makeNotificationItem)
                    )
                )
            } catch {
                return AIService.encodeToolExecutionError(
                    .init(error: "工具参数解析失败：\(error.localizedDescription)")
                )
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            let arguments = try? JSONDecoder().decode(
                DeletePendingNotificationsToolArguments.self,
                from: Data(argumentsJSON.utf8)
            )
            let hasSpecificTarget = !(arguments?.notificationId?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ?? true)

            return .init(
                text: hasSpecificTarget
                    ? "已调用“删除指定未触发通知”"
                    : "已调用“删除未触发通知”",
                functionName: functionName,
                category: category,
                invocationKey: hasSpecificTarget
                    ? "\(functionName)|\(arguments?.notificationId ?? "")"
                    : functionName
            )
        }
    }

    private static func makeNotificationItem(
        from record: ScheduledToolNotificationRecord
    ) -> ToolNotificationItem {
        ToolNotificationItem(
            notificationId: record.id,
            title: record.title,
            content: record.body,
            scheduledAtBeijing: ToolNotificationService.formattedBeijingDateTime(
                record.scheduledAt
            ),
            scheduledTimeMs: ToolNotificationService.scheduledTimestampMilliseconds(
                for: record.scheduledAt
            )
        )
    }
}
