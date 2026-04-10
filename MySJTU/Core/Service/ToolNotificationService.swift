//
//  ToolNotificationService.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation
import UserNotifications

struct ScheduledToolNotificationRecord: Codable, Equatable, Identifiable {
    let id: String
    let body: String
    let scheduledAt: Date
    let createdAt: Date

    var title: String {
        ToolNotificationService.fixedTitle
    }
}

enum ToolNotificationServiceError: LocalizedError {
    case noPermission
    case invalidDate
    case pastDate
    case emptyContent
    case schedulingFailed

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "没有推送通知权限"
        case .invalidDate:
            return "通知时间无效，请检查年月日和时间。"
        case .pastDate:
            return "通知时间已过，请设置未来的时间。"
        case .emptyContent:
            return "通知内容不能为空。"
        case .schedulingFailed:
            return "通知创建失败，请稍后重试。"
        }
    }
}

struct PresentedToolNotificationAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
}

@MainActor
final class ToolNotificationAlertCenter: ObservableObject {
    static let shared = ToolNotificationAlertCenter()

    @Published var activeAlert: PresentedToolNotificationAlert?

    private init() {}

    func present(identifier: String, body: String) {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            return
        }

        activeAlert = PresentedToolNotificationAlert(
            id: identifier,
            title: ToolNotificationService.fixedTitle,
            body: trimmedBody
        )
    }

    func dismiss() {
        activeAlert = nil
    }
}

actor ToolNotificationService {
    static let shared = ToolNotificationService()
    static let fixedTitle = "定时提醒"

    private static let storageKey = "ai.tool.notifications"
    private static let requestIdentifierPrefix = "ai_notification_"
    private static let userInfoTypeKey = "ai_tool_call_type"
    private static let userInfoTypeValue = "notification"

    private let notificationCenter: UNUserNotificationCenter
    private let userDefaults: UserDefaults

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        userDefaults: UserDefaults = .standard
    ) {
        self.notificationCenter = notificationCenter
        self.userDefaults = userDefaults
    }

    func scheduleNotification(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        body: String
    ) async throws -> ScheduledToolNotificationRecord {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else {
            throw ToolNotificationServiceError.emptyContent
        }

        guard let scheduledAt = Self.makeBeijingDate(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ) else {
            throw ToolNotificationServiceError.invalidDate
        }

        guard scheduledAt > Date() else {
            throw ToolNotificationServiceError.pastDate
        }

        guard await hasNotificationPermission() else {
            throw ToolNotificationServiceError.noPermission
        }

        _ = await reconcilePersistedNotifications(now: .now)

        let identifier = Self.requestIdentifierPrefix + UUID().uuidString.lowercased()
        let triggerComponents = Self.makeTriggerComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )

        let content = UNMutableNotificationContent()
        content.title = Self.fixedTitle
        content.body = trimmedBody
        content.sound = .default
        content.userInfo = [
            Self.userInfoTypeKey: Self.userInfoTypeValue
        ]

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: triggerComponents,
                repeats: false
            )
        )

        do {
            try await notificationCenter.sjtuAdd(request)
        } catch {
            throw ToolNotificationServiceError.schedulingFailed
        }

        let record = ScheduledToolNotificationRecord(
            id: identifier,
            body: trimmedBody,
            scheduledAt: scheduledAt,
            createdAt: .now
        )

        var storedRecords = loadStoredRecords()
        storedRecords.removeAll { $0.id == identifier }
        storedRecords.append(record)
        saveStoredRecords(storedRecords.sorted(by: Self.sortRecords))

        return record
    }

    func pendingNotifications() async -> [ScheduledToolNotificationRecord] {
        await reconcilePersistedNotifications(now: .now)
    }

    func deletePendingNotifications(
        notificationID: String?
    ) async -> [ScheduledToolNotificationRecord] {
        let currentRecords = await reconcilePersistedNotifications(now: .now)
        let trimmedNotificationID = notificationID?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let targetRecords: [ScheduledToolNotificationRecord]
        if let trimmedNotificationID, !trimmedNotificationID.isEmpty {
            targetRecords = currentRecords.filter { $0.id == trimmedNotificationID }
        } else {
            targetRecords = currentRecords
        }

        guard !targetRecords.isEmpty else {
            return []
        }

        let identifiers = targetRecords.map(\.id)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
        removeStoredNotifications(withIdentifiers: identifiers)
        return targetRecords.sorted(by: Self.sortRecords)
    }

    func cleanupExpiredPersistedNotifications() async {
        _ = await reconcilePersistedNotifications(now: .now)
    }

    func handleTriggeredNotification(_ notification: UNNotification) async {
        guard Self.isManagedNotification(notification.request) else {
            return
        }

        let identifier = notification.request.identifier
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
        removeStoredNotifications(withIdentifiers: [identifier])

        await MainActor.run {
            ToolNotificationAlertCenter.shared.present(
                identifier: identifier,
                body: notification.request.content.body
            )
        }
    }

    nonisolated static func isManagedNotification(_ request: UNNotificationRequest) -> Bool {
        if request.identifier.hasPrefix(requestIdentifierPrefix) {
            return true
        }

        return request.content.userInfo[userInfoTypeKey] as? String == userInfoTypeValue
    }

    nonisolated static func isManagedNotification(_ notification: UNNotification) -> Bool {
        isManagedNotification(notification.request)
    }

    nonisolated static func formattedBeijingDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = beijingCalendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = beijingTimeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    nonisolated static func scheduledTimestampMilliseconds(
        for date: Date
    ) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    nonisolated private static var beijingTimeZone: TimeZone {
        TimeZone(identifier: "Asia/Shanghai")
            ?? TimeZone(secondsFromGMT: 8 * 60 * 60)
            ?? .current
    }

    nonisolated private static var beijingCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = beijingTimeZone
        return calendar
    }

    nonisolated private static func makeTriggerComponents(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> DateComponents {
        var components = DateComponents()
        components.calendar = beijingCalendar
        components.timeZone = beijingTimeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return components
    }

    nonisolated private static func makeBeijingDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int
    ) -> Date? {
        guard (1...12).contains(month),
              (1...31).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        let components = makeTriggerComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )

        guard let date = beijingCalendar.date(from: components) else {
            return nil
        }

        let resolved = beijingCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        guard resolved.year == year,
              resolved.month == month,
              resolved.day == day,
              resolved.hour == hour,
              resolved.minute == minute else {
            return nil
        }

        return date
    }

    private func hasNotificationPermission() async -> Bool {
        let settings = await notificationCenter.sjtuNotificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return Self.canPresentAlert(using: settings)
        case .notDetermined:
            do {
                let granted = try await notificationCenter.sjtuRequestAuthorization(
                    options: [.alert, .sound, .badge]
                )
                guard granted else {
                    return false
                }
                let refreshedSettings = await notificationCenter.sjtuNotificationSettings()
                return Self.canPresentAlert(using: refreshedSettings)
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func reconcilePersistedNotifications(
        now: Date
    ) async -> [ScheduledToolNotificationRecord] {
        let pendingRequests = await notificationCenter.sjtuPendingNotificationRequests()
        let pendingIdentifiers = Set(
            pendingRequests
                .filter(Self.isManagedNotification)
                .map(\.identifier)
        )

        let currentRecords = loadStoredRecords()
        let filteredRecords = currentRecords
            .filter { record in
                record.scheduledAt > now && pendingIdentifiers.contains(record.id)
            }
            .sorted(by: Self.sortRecords)

        if filteredRecords != currentRecords {
            saveStoredRecords(filteredRecords)
        }

        return filteredRecords
    }

    private func loadStoredRecords() -> [ScheduledToolNotificationRecord] {
        guard let rawValue = userDefaults.string(forKey: Self.storageKey),
              let records = [ScheduledToolNotificationRecord](rawValue: rawValue) else {
            return []
        }

        return records.sorted(by: Self.sortRecords)
    }

    private func saveStoredRecords(_ records: [ScheduledToolNotificationRecord]) {
        if records.isEmpty {
            userDefaults.removeObject(forKey: Self.storageKey)
        } else {
            userDefaults.set(records.rawValue, forKey: Self.storageKey)
        }
    }

    private func removeStoredNotifications(withIdentifiers identifiers: [String]) {
        let identifierSet = Set(identifiers)
        let filteredRecords = loadStoredRecords()
            .filter { !identifierSet.contains($0.id) }
            .sorted(by: Self.sortRecords)
        saveStoredRecords(filteredRecords)
    }

    nonisolated private static func sortRecords(
        _ lhs: ScheduledToolNotificationRecord,
        _ rhs: ScheduledToolNotificationRecord
    ) -> Bool {
        if lhs.scheduledAt != rhs.scheduledAt {
            return lhs.scheduledAt < rhs.scheduledAt
        }

        return lhs.createdAt < rhs.createdAt
    }

    nonisolated private static func canPresentAlert(
        using settings: UNNotificationSettings
    ) -> Bool {
        switch settings.alertSetting {
        case .enabled:
            return true
        case .disabled, .notSupported:
            return false
        @unknown default:
            return false
        }
    }
}

private extension UNUserNotificationCenter {
    func sjtuNotificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { (
            continuation: CheckedContinuation<UNNotificationSettings, Never>
        ) in
            getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    func sjtuRequestAuthorization(
        options: UNAuthorizationOptions
    ) async throws -> Bool {
        try await withCheckedThrowingContinuation { (
            continuation: CheckedContinuation<Bool, Error>
        ) in
            requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func sjtuAdd(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (
            continuation: CheckedContinuation<Void, Error>
        ) in
            add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func sjtuPendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { (
            continuation: CheckedContinuation<[UNNotificationRequest], Never>
        ) in
            getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }
}
