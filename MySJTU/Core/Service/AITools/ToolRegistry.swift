//
//  ToolRegistry.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    enum ToolRegistry {
        static let capabilityProbe = CapabilityProbeToolDefinition()
        static let currentDataSourceSemester = CurrentDataSourceSemesterToolDefinition()
        static let currentDataSourceSchedules = CurrentDataSourceSchedulesToolDefinition()
        static let semesterExamArrangements = SemesterExamArrangementsToolDefinition()
        static let semesterGrades = SemesterGradesToolDefinition()
        static let gpaStatistics = GPAStatisticsToolDefinition()
        static let canvasTodoItems = CanvasTodoItemsToolDefinition()
        static let selfStudyBuildingRooms = SelfStudyBuildingRoomsToolDefinition()
        static let selfStudyRoomRealtimeStatus = SelfStudyRoomRealtimeStatusToolDefinition()
        static let openJAccountAccount = OpenJAccountAccountToolDefinition()
        static let userProfile = UserProfileToolDefinition()
        static let campusCardInformation = CampusCardInformationToolDefinition()
        static let campusCardTransactions = CampusCardTransactionsToolDefinition()
        static let campusCardCostAnalytics = CampusCardCostAnalyticsToolDefinition()
        static let scheduleNotification = ScheduleNotificationToolDefinition()
        static let pendingNotifications = PendingNotificationsToolDefinition()
        static let deletePendingNotifications = DeletePendingNotificationsToolDefinition()

        static let all: [ToolDefinition] = [
            capabilityProbe,
            currentDataSourceSemester,
            currentDataSourceSchedules,
            semesterExamArrangements,
            semesterGrades,
            gpaStatistics,
            canvasTodoItems,
            selfStudyBuildingRooms,
            selfStudyRoomRealtimeStatus,
            openJAccountAccount,
            userProfile,
            campusCardInformation,
            campusCardTransactions,
            campusCardCostAnalytics,
            scheduleNotification,
            pendingNotifications,
            deletePendingNotifications
        ]

        static let toolsByFunctionName = Dictionary(
            uniqueKeysWithValues: all.map { ($0.functionName, $0) }
        )

        static let availableChatTools = all
            .filter(\.isAvailableInChat)
            .map(\.tool)

        static func tool(for functionName: String) -> ToolDefinition? {
            toolsByFunctionName[functionName]
        }
    }

    static func toolDisplayName(for functionName: String) -> String {
        ToolRegistry.tool(for: functionName)?.displayName ?? functionName
    }

    static func toolCategory(for functionName: String) -> AIToolCallCategory? {
        ToolRegistry.tool(for: functionName)?.category
    }

    static func toolRequiresUserAuthorization(for functionName: String) -> Bool {
        ToolRegistry.tool(for: functionName)?.requiresUserAuthorization ?? true
    }
}
