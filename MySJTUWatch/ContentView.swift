//
//  ContentView.swift
//  MySJTUWatch Watch App
//
//  Created by boar on 2026/03/27.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: WatchScheduleStore

    private var snapshot: WatchScheduleSnapshot? {
        store.snapshot
    }

    private func daySnapshot(for date: Date) -> WatchScheduleDaySnapshot? {
        snapshot?.days.first(where: { $0.date.watchScheduleDay == date.watchScheduleDay })
    }

    var body: some View {
        NavigationStack {
            Group {
                if snapshot != nil {
                    WatchScheduleHomeView(
                        today: daySnapshot(for: .now),
                        tomorrow: daySnapshot(for: Date.now.addingTimeInterval(24 * 3600))
                    )
                } else {
                    WatchSyncPlaceholderView(
                        title: store.isCompanionAppInstalled ? "等待同步日程" : "未连接 iPhone",
                        message: store.isCompanionAppInstalled
                        ? "请先打开 iPhone 上的交课表，同步完成后就能在手表查看日程。"
                        : "安装并打开 iPhone 上的交课表后，这里会自动出现同步过来的日程。",
                        canRefresh: store.isReachable,
                        onRefresh: store.requestRefreshIfPossible
                    )
                }
            }
            .navigationTitle("交课表")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WatchMoreView()
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                store.requestRefreshIfPossible()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchScheduleStore.preview)
}

private struct WatchScheduleHomeView: View {
    let today: WatchScheduleDaySnapshot?
    let tomorrow: WatchScheduleDaySnapshot?

    var body: some View {
        List {
            Section("今天") {
                if let today, !today.items.isEmpty {
                    ForEach(today.items) { item in
                        WatchScheduleCard(item: item)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    WatchEmptyDayCard(message: "今天没有已同步的日程")
                        .listRowBackground(Color.clear)
                }
            }

            Section("明天") {
                if let tomorrow, !tomorrow.items.isEmpty {
                    ForEach(tomorrow.items) { item in
                        WatchScheduleCard(item: item)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    WatchEmptyDayCard(message: "明天没有已同步的日程")
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.carousel)
    }
}

private struct WatchScheduleCard: View {
    let item: WatchScheduleItemSnapshot

    private var accentColor: Color {
        Color(hex: item.colorHex)
    }

    private var state: WatchScheduleCardState {
        if item.endAt <= .now {
            return .past
        }

        if item.startAt <= .now {
            return .ongoing
        }

        return .upcoming
    }

    private var detailText: String {
        let startTime = WatchFormatters.time.string(from: item.startAt)
        guard !item.subtitle.isEmpty else {
            return startTime
        }

        return "\(startTime)・\(item.subtitle)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(state.titleStyle(accentColor: accentColor))
                    .lineLimit(2)

                Spacer(minLength: 0)

                if let statusText = state.statusText {
                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            Capsule(style: .continuous)
                                .fill(state.badgeBackground(accentColor: accentColor))
                        }
                        .foregroundStyle(state.badgeForeground(accentColor: accentColor))
                }
            }

            Text(detailText)
                .font(.footnote)
                .foregroundStyle(state.detailStyle(accentColor: accentColor))
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(state.background(accentColor: accentColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(state.border(accentColor: accentColor), lineWidth: state == .ongoing ? 1.4 : 1)
        }
        .opacity(state == .past ? 0.74 : 1)
    }
}

private struct WatchEmptyDayCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.headline)

            Text("如有遗漏，可以在“更多”里从 iPhone 进行同步。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
        }
    }
}

private struct WatchSyncPlaceholderView: View {
    let title: String
    let message: String
    let canRefresh: Bool
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "applewatch.watchface")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)

                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("尝试同步", action: onRefresh)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRefresh)
            }
            .padding()
        }
    }
}

enum WatchCalendar {
    static var current: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }
}

enum WatchFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = WatchCalendar.current
        formatter.timeZone = WatchCalendar.current.timeZone
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

extension Date {
    var watchScheduleDay: Date {
        WatchCalendar.current.startOfDay(for: self)
    }
}

private extension Color {
    init(hex: String) {
        let sanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self = Color(red: red, green: green, blue: blue)
    }
}

private enum WatchScheduleCardState {
    case upcoming
    case ongoing
    case past

    var statusText: String? {
        switch self {
        case .upcoming:
            return nil
        case .ongoing:
            return "进行中"
        case .past:
            return "已结束"
        }
    }

    func background(accentColor: Color) -> Color {
        switch self {
        case .upcoming:
            return accentColor.opacity(0.16)
        case .ongoing:
            return accentColor.opacity(0.28)
        case .past:
            return Color.gray.opacity(0.12)
        }
    }

    func border(accentColor: Color) -> Color {
        switch self {
        case .upcoming:
            return accentColor.opacity(0.32)
        case .ongoing:
            return accentColor.opacity(0.82)
        case .past:
            return Color.gray.opacity(0.2)
        }
    }

    func titleStyle(accentColor: Color) -> Color {
        switch self {
        case .upcoming:
            return .primary
        case .ongoing:
            return accentColor
        case .past:
            return .secondary
        }
    }

    func detailStyle(accentColor: Color) -> Color {
        switch self {
        case .upcoming:
            return .secondary
        case .ongoing:
            return accentColor.opacity(0.9)
        case .past:
            return .secondary.opacity(0.9)
        }
    }

    func badgeBackground(accentColor: Color) -> Color {
        switch self {
        case .upcoming:
            return .clear
        case .ongoing:
            return accentColor.opacity(0.2)
        case .past:
            return Color.gray.opacity(0.16)
        }
    }

    func badgeForeground(accentColor: Color) -> Color {
        switch self {
        case .upcoming:
            return .clear
        case .ongoing:
            return accentColor
        case .past:
            return .secondary
        }
    }
}
