//
//  AnalyticsService.swift
//  MySJTU
//
//  Created by Codex on 2026/04/11.
//

import Foundation
import FirebaseAnalytics

enum AnalyticsService {
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let staticDefaultParameters: [String: Any] = {
        [
            "app_ver": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "app_build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        ]
    }()

    static func configure() {
        Analytics.setAnalyticsCollectionEnabled(true)
        Analytics.setDefaultEventParameters(staticDefaultParameters)
    }

    static func logScreen(
        _ name: String,
        screenClass: String? = nil,
        parameters: [String: Any] = [:]
    ) {
        var payload = parameters
        payload[AnalyticsParameterScreenName] = name
        payload[AnalyticsParameterScreenClass] = screenClass ?? name
        Analytics.logEvent(
            AnalyticsEventScreenView,
            parameters: normalize(parameters: payload)
        )
    }

    static func logEvent(
        _ name: String,
        parameters: [String: Any] = [:]
    ) {
        Analytics.logEvent(name, parameters: normalize(parameters: parameters))
    }

    static func syncUserContext(
        accounts: [WebAuthAccount],
        appStatus: AppConfig.AppStatus,
        displayMode: DisplayMode,
        aiConfig: AIConfig
    ) {
        let hasJAccount = accounts.contains { $0.provider == .jaccount }
        let hasCanvas = accounts.contains {
            $0.provider == .jaccount
                && $0.enabledFeatures.contains(.canvas)
                && $0.bizData["canvas_token"]?.isEmpty == false
        }
        let hasUnicode = accounts.contains {
            $0.provider == .jaccount && $0.enabledFeatures.contains(.unicode)
        }
        let hasExam = accounts.contains {
            $0.provider == .jaccount && $0.enabledFeatures.contains(.examAndGrade)
        }
        let hasCampusCard = accounts.contains {
            $0.provider == .jaccount && $0.enabledFeatures.contains(.campusCard)
        }
        let connectedCount = accounts.filter { $0.status == .connected }.count

        let dynamicDefaults: [String: Any] = [
            "app_status": appStatus.analyticsValue,
            "disp_mode": displayMode.analyticsValue,
            "acct_count": accounts.count,
            "acct_conn": connectedCount,
            "has_jacct": hasJAccount,
            "has_canvas": hasCanvas,
            "has_unicode": hasUnicode,
            "has_exam": hasExam,
            "has_card": hasCampusCard,
            "ai_ready": aiConfig.hasValidConfiguration,
            "ai_provider": aiConfig.provider?.analyticsValue ?? "none",
            "ai_tools": aiConfig.capabilities.supportsToolCalling ?? false
        ]

        Analytics.setDefaultEventParameters(
            normalize(parameters: staticDefaultParameters.merging(dynamicDefaults) { _, new in new })
        )

        setUserProperty(appStatus.analyticsValue, forName: "app_status")
        setUserProperty(displayMode.analyticsValue, forName: "disp_mode")
        setUserProperty(String(accounts.count), forName: "acct_count")
        setUserProperty(String(connectedCount), forName: "acct_conn")
        setUserProperty(boolString(hasJAccount), forName: "has_jacct")
        setUserProperty(boolString(hasCanvas), forName: "has_canvas")
        setUserProperty(boolString(hasUnicode), forName: "has_unicode")
        setUserProperty(boolString(hasExam), forName: "has_exam")
        setUserProperty(boolString(hasCampusCard), forName: "has_card")
        setUserProperty(boolString(aiConfig.hasValidConfiguration), forName: "ai_ready")
        setUserProperty(aiConfig.provider?.analyticsValue ?? "none", forName: "ai_provider")
        setUserProperty(
            boolString(aiConfig.capabilities.supportsToolCalling ?? false),
            forName: "ai_tools"
        )
    }

    static func messageLengthBucket(for text: String) -> String {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        switch count {
        case 0:
            return "empty"
        case 1...20:
            return "1_20"
        case 21...60:
            return "21_60"
        case 61...160:
            return "61_160"
        default:
            return "161_plus"
        }
    }

    static func errorTypeName(_ error: Error) -> String {
        String(describing: type(of: error))
    }

    static func dayOffsetFromToday(for date: Date) -> Int {
        Calendar.current.dateComponents(
            [.day],
            from: Date.now.startOfDay(),
            to: date.startOfDay()
        ).day ?? 0
    }

    static func timestampString(_ date: Date = .now) -> String {
        timestampFormatter.string(from: date)
    }

    private static func normalize(parameters: [String: Any]) -> [String: Any] {
        parameters.reduce(into: [String: Any]()) { result, element in
            let (key, value) = element
            guard let normalizedValue = normalize(value) else {
                return
            }

            result[key] = normalizedValue
        }
    }

    private static func normalize(_ value: Any) -> Any? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let bool as Bool:
            return bool ? 1 : 0
        case let int as Int:
            return int
        case let int8 as Int8:
            return Int(int8)
        case let int16 as Int16:
            return Int(int16)
        case let int32 as Int32:
            return Int(int32)
        case let int64 as Int64:
            return int64
        case let uint as UInt:
            return Int(uint)
        case let uint8 as UInt8:
            return Int(uint8)
        case let uint16 as UInt16:
            return Int(uint16)
        case let uint32 as UInt32:
            return Int(uint32)
        case let double as Double:
            return double.isFinite ? double : nil
        case let float as Float:
            return float.isFinite ? Double(float) : nil
        case let number as NSNumber:
            return number
        case let date as Date:
            return timestampFormatter.string(from: date)
        case let optional as OptionalProtocol:
            return optional.analyticsWrappedValue.flatMap(normalize(_:))
        default:
            return String(describing: value)
        }
    }

    private static func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    private static func boolString(_ value: Bool) -> String {
        value ? "1" : "0"
    }
}

private protocol OptionalProtocol {
    var analyticsWrappedValue: Any? { get }
}

extension Optional: OptionalProtocol {
    fileprivate var analyticsWrappedValue: Any? {
        switch self {
        case .some(let value):
            return value
        case .none:
            return nil
        }
    }
}

extension AppConfig.AppStatus {
    var analyticsValue: String {
        switch self {
        case .normal:
            return "normal"
        case .review:
            return "review"
        }
    }
}

extension DisplayMode {
    var analyticsValue: String {
        switch self {
        case .day:
            return "day"
        case .week:
            return "week"
        }
    }
}

extension Provider {
    var analyticsValue: String {
        switch self {
        case .jaccount:
            return "jaccount"
        case .shsmu:
            return "shsmu"
        }
    }
}

extension Feature {
    var analyticsValue: String {
        switch self {
        case .schedule:
            return "schedule"
        case .examAndGrade:
            return "exam_grade"
        case .unicode:
            return "unicode"
        case .campusCard:
            return "campus_card"
        case .canvas:
            return "canvas"
        }
    }
}

extension AIProvider {
    var analyticsValue: String {
        rawValue
    }
}

extension WebAuthStatus {
    var analyticsValue: String {
        switch self {
        case .connected:
            return "connected"
        case .disconnected:
            return "disconnected"
        case .expired:
            return "expired"
        case .error:
            return "error"
        }
    }
}

extension College {
    var analyticsValue: String {
        switch self {
        case .sjtu:
            return "sjtu"
        case .sjtug:
            return "sjtug"
        case .joint:
            return "joint"
        case .shsmu:
            return "shsmu"
        }
    }
}
