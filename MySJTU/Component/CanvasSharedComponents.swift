//
//  CanvasSharedComponents.swift
//  MySJTU
//
//  Created by boar on 2026/03/28.
//

import SwiftUI

extension Array where Element == WebAuthAccount {
    var jaccountAccount: WebAuthAccount? {
        first { $0.provider == .jaccount }
    }

    var jaccountCanvasToken: String? {
        guard let account = jaccountAccount,
              account.enabledFeatures.contains(.canvas),
              let token = account.bizData["canvas_token"]
        else {
            return nil
        }
        return token
    }
}

enum CanvasDateSortOrder {
    case ascending
    case descending
}

enum CanvasFormatters {
    static let iso8601 = ISO8601DateFormatter()

    static let score: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

func canvasCompareDates(
    _ lhs: Date?,
    _ rhs: Date?,
    order: CanvasDateSortOrder,
    fallback: @autoclosure () -> Bool
) -> Bool {
    switch (lhs, rhs) {
    case let (lhs?, rhs?):
        switch order {
        case .ascending:
            return lhs == rhs ? fallback() : lhs < rhs
        case .descending:
            return lhs == rhs ? fallback() : lhs > rhs
        }
    case (.some, .none):
        return true
    case (.none, .some):
        return false
    case (.none, .none):
        return fallback()
    }
}

extension Date {
    func formattedCanvasAbsoluteDate(using calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(self) {
            return "今天 \(formatted(date: .omitted, time: .shortened))"
        }

        if calendar.isDateInTomorrow(self) {
            return "明天 \(formatted(date: .omitted, time: .shortened))"
        }

        if calendar.isDateInYesterday(self) {
            return "昨天 \(formatted(date: .omitted, time: .shortened))"
        }

        return formatted(date: .abbreviated, time: .shortened)
    }

    func formattedCanvasRelativeDueDate(includeOverduePrefix: Bool = false) -> String {
        let text = "\(formattedRelativeDate()) \(formatted(date: .omitted, time: .shortened))"
        return includeOverduePrefix ? "已于 \(text) 截止" : text
    }
}

struct CanvasLoadingView: View {
    let title: String

    var body: some View {
        ProgressView(title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CanvasInfoRow: View {
    let title: String
    let value: String
    var multiline: Bool = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(multiline ? .trailing : .leading)
        }
    }
}

struct CanvasSectionHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            CanvasSectionHeaderIcon(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CanvasSectionHeaderIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))

            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 28, height: 28)
    }
}

struct CanvasMetadataItem: Identifiable {
    let systemImage: String
    let text: String

    var id: String {
        "\(systemImage)-\(text)"
    }
}

struct CanvasMetadataGroup: View {
    let items: [CanvasMetadataItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                metadataContent
            }

            VStack(alignment: .leading, spacing: 6) {
                metadataContent
            }
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var metadataContent: some View {
        ForEach(items) { item in
            HStack(spacing: 4) {
                Image(systemName: item.systemImage)
                    .font(.caption2.weight(.semibold))
                    .frame(width: 10)

                Text(item.text)
                    .lineLimit(1)
            }
            .font(.footnote)
        }
    }
}

struct CanvasStatusPresentation {
    let title: String
    let tint: Color
    let score: Double?
    let pointsPossible: Double?

    init(
        title: String,
        tint: Color,
        score: Double? = nil,
        pointsPossible: Double? = nil
    ) {
        self.title = title
        self.tint = tint
        self.score = score
        self.pointsPossible = pointsPossible
    }
}

struct CanvasStatusView: View {
    let presentation: CanvasStatusPresentation

    var body: some View {
        Group {
            if let score = presentation.score {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formattedScore(score))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(presentation.tint)

                    if let pointsPossible = presentation.pointsPossible, pointsPossible > 0 {
                        Text("/ \(formattedScore(pointsPossible))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(presentation.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                statusBadge(presentation.title, tint: presentation.tint)
            }
        }
        .frame(minWidth: 58, alignment: .trailing)
    }

    private func statusBadge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
            )
    }

    private func formattedScore(_ value: Double) -> String {
        CanvasFormatters.score.string(from: NSNumber(value: value)) ?? value.clean
    }
}
