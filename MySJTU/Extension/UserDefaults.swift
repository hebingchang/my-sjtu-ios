//
//  UserDefaults.swift
//  MySJTU
//
//  Created by boar on 2024/11/09.
//

import CoreGraphics
import Foundation

public extension UserDefaults {
    static let appGroupIdentifier = "group.com.boar.sjct"
    static let shared = UserDefaults(suiteName: UserDefaults.appGroupIdentifier)!
}

enum WidgetBackgroundSlot: String, CaseIterable, Identifiable {
    case systemSmall
    case systemMedium
    case systemLarge

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .systemSmall:
            return "小号小组件"
        case .systemMedium:
            return "中号小组件"
        case .systemLarge:
            return "大号小组件"
        }
    }

    var subtitle: String {
        switch self {
        case .systemSmall:
            return "适合只看粗略信息"
        case .systemMedium:
            return "展示日程完整信息"
        case .systemLarge:
            return "适合展示更多日程"
        }
    }

    var storageKey: String {
        "widget.background.\(rawValue)"
    }

    var transparencyKey: String {
        "\(storageKey).transparency"
    }

    var blurRadiusKey: String {
        "\(storageKey).blurRadius"
    }

    var aspectRatio: CGFloat {
        switch self {
        case .systemSmall:
            return 1
        case .systemMedium:
            return 364.0 / 170.0
        case .systemLarge:
            return 364.0 / 382.0
        }
    }
}

struct WidgetBackgroundEffectConfiguration: Equatable {
    static let defaultTransparency = 0.35
    static let defaultBlurRadius = 18.0
    static let transparencyRange: ClosedRange<Double> = 0.0...0.8
    static let blurRadiusRange: ClosedRange<Double> = 0.0...30.0

    let transparency: Double
    let blurRadius: Double

    var clampedTransparency: Double {
        min(max(transparency, Self.transparencyRange.lowerBound), Self.transparencyRange.upperBound)
    }

    var clampedBlurRadius: Double {
        min(max(blurRadius, Self.blurRadiusRange.lowerBound), Self.blurRadiusRange.upperBound)
    }

    var imageOpacity: Double {
        max(0.2, 1 - clampedTransparency * 0.6)
    }

    var topOverlayOpacity: Double {
        0.18 + clampedTransparency * 0.24
    }

    var middleOverlayOpacity: Double {
        0.36 + clampedTransparency * 0.34
    }

    var bottomOverlayOpacity: Double {
        0.52 + clampedTransparency * 0.32
    }

    var flatOverlayOpacity: Double {
        0.08 + clampedTransparency * 0.34
    }

    var usesDefaultValues: Bool {
        abs(clampedTransparency - Self.defaultTransparency) < 0.001 &&
        abs(clampedBlurRadius - Self.defaultBlurRadius) < 0.001
    }

    static var defaultValue: Self {
        Self(
            transparency: defaultTransparency,
            blurRadius: defaultBlurRadius
        )
    }
}

enum SharedContainerDirectory {
    static let widgetBackgroundDirectoryName = "WidgetBackgrounds"

    static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: UserDefaults.appGroupIdentifier)
    }

    static func widgetBackgroundsURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?
            .appendingPathComponent(widgetBackgroundDirectoryName, isDirectory: true)
    }

    static func widgetBackgroundURL(
        for filename: String,
        fileManager: FileManager = .default
    ) -> URL? {
        guard !filename.isEmpty else { return nil }

        return widgetBackgroundsURL(fileManager: fileManager)?
            .appendingPathComponent(filename, isDirectory: false)
    }
}


extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}
