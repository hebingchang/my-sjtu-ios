//
//  NotificationView.swift
//  MySJTU
//
//  Created by boar on 2024/12/13.
//

import SwiftUI
import FeedKit

struct NotificationView: View {
    private static let pageSize: Int = 20
    
    @State private var loading: Bool = true
    @State private var loadingMore: Bool = false
    @State private var hasMore: Bool = true
    @State private var requestedItemCount: Int = pageSize
    @State private var dailyFeeds: [DailyFeeds] = []
    @State private var lastUpdatedAt: Date?
    @State private var loadErrorMessage: String?
    @State private var selectedURL: IdentifiableURL?
    
    @Environment(\.colorScheme) private var colorScheme
    
    private static let feedURLString = "https://jwc.sjtu.edu.cn/system/resource/code/rss/rssfeed.jsp?type=list&treeid=1292&viewid=1011878&mode=10&dbname=vsb&owner=1707467176&ownername=jwc2021&contentid=1015253&number=20&httproot="
    private static let sectionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()
    private static let updateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
    
    private struct DailyFeeds {
        let id: String
        let date: Date?
        let items: [FeedItem]
        
        var title: String {
            guard let date else {
                return "未标注日期"
            }
            
            if Calendar.iso8601.isDateInToday(date) {
                return "今天"
            }
            
            if Calendar.iso8601.isDateInYesterday(date) {
                return "昨天"
            }
            
            return NotificationView.sectionDateFormatter.string(from: date)
        }
    }
    
    private struct FeedItem: Identifiable {
        let id: String
        let title: String
        let summary: String
        let publishedAt: Date?
        let url: URL?
    }

    private struct IdentifiableURL: Identifiable {
        public var id: URL
    }
    
    private var totalFeedCount: Int {
        dailyFeeds.reduce(0) { $0 + $1.items.count }
    }
    
    private static func feedURL(limit: Int) -> URL {
        var components = URLComponents(string: feedURLString)!
        var queryItems = components.queryItems ?? []
        
        if let index = queryItems.firstIndex(where: { $0.name == "number" }) {
            queryItems[index] = URLQueryItem(name: "number", value: "\(limit)")
        } else {
            queryItems.append(URLQueryItem(name: "number", value: "\(limit)"))
        }
        
        components.queryItems = queryItems
        
        return components.url!
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.systemGroupedBackground,
                Color.secondarySystemGroupedBackground.opacity(0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在更新教务通知...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("暂无通知", systemImage: "bell.slash")
        } description: {
            Text(loadErrorMessage ?? "当前没有可显示的教务通知。")
        } actions: {
            Button("重试") {
                Task {
                    await loadFeed(showsLoading: true)
                }
            }
        }
    }
    
    @ViewBuilder
    private var loadMoreFooter: some View {
        if loadingMore {
            HStack(spacing: 8) {
                Spacer()
                ProgressView()
                Text("正在加载更多...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else if hasMore {
            HStack(spacing: 8) {
                Spacer()
                ProgressView()
                    .controlSize(.small)
                Text("继续下拉加载更多")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .onAppear {
                Task {
                    await loadMore()
                }
            }
        } else if !dailyFeeds.isEmpty {
            HStack {
                Spacer()
                Text("已加载全部通知")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
    
    private var lastUpdatedText: String {
        guard let lastUpdatedAt else {
            return "尚未更新"
        }
        
        return "更新于 \(Self.updateTimeFormatter.string(from: lastUpdatedAt))"
    }
    
    private func sectionHeader(for day: DailyFeeds) -> some View {
        HStack {
            Text(day.title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text("\(day.items.count) 条")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }
    
    private func feedCard(_ item: FeedItem) -> some View {
        Button {
            guard let url = item.url else {
                return
            }
            AnalyticsService.logEvent(
                "notification_opened",
                parameters: [
                    "has_summary": !item.summary.isEmpty,
                    "host": url.host() ?? "unknown"
                ]
            )
            selectedURL = IdentifiableURL(id: url)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.16))
                    Image(systemName: item.url == nil ? "doc.text.fill" : "arrow.up.forward.app.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .frame(width: 34, height: 34)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    HStack(spacing: 10) {
                        if let publishedAt = item.publishedAt {
                            metadataTag(
                                systemImage: "clock",
                                text: publishedAt.formatted(
                                    date: .omitted,
                                    time: .shortened
                                )
                            )
                        }
                        
                        if let host = item.url?.host(), !host.isEmpty {
                            metadataTag(systemImage: "globe", text: host)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                
                Spacer(minLength: 8)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 6)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(NotificationCardButtonStyle(enabled: item.url != nil))
        .disabled(item.url == nil)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    
    private func metadataTag(systemImage: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
            Text(text)
        }
    }
    
    private func normalizedText(_ text: String?) -> String {
        guard let text else {
            return ""
        }
        
        return text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func mapItem(_ item: RSSFeedItem) -> FeedItem {
        let title = normalizedText(item.title)
        let summary = normalizedText(item.description)
        let cleanedTitle = title.isEmpty ? "未命名通知" : title
        let id = item.guid?.value ?? "\(item.link ?? cleanedTitle)-\(item.pubDate?.timeIntervalSince1970 ?? 0)"
        
        return FeedItem(
            id: id,
            title: cleanedTitle,
            summary: summary,
            publishedAt: item.pubDate,
            url: item.link.flatMap(URL.init(string:))
        )
    }
    
    private func groupByDate(_ items: [FeedItem]) -> [DailyFeeds] {
        let grouped = Dictionary(grouping: items) { item -> String in
            if let publishedAt = item.publishedAt {
                return publishedAt.formattedDate()
            } else {
                return "unknown"
            }
        }
        
        let mapped = grouped.map { key, value in
            let date = key == "unknown" ? nil : Date.fromFormat("yyyy-MM-dd", dateStr: key)
            let sortedItems = value.sorted {
                ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast)
            }
            
            return DailyFeeds(
                id: key,
                date: date,
                items: sortedItems
            )
        }
        
        return mapped.sorted { left, right in
            switch (left.date, right.date) {
            case let (.some(l), .some(r)):
                return l > r
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left.id < right.id
            }
        }
    }
    
    private func fetchItems(limit: Int) async throws -> [RSSFeedItem] {
        try await withCheckedThrowingContinuation { continuation in
            let parser = FeedParser(URL: Self.feedURL(limit: limit))
            parser.parseAsync(queue: DispatchQueue.global(qos: .userInitiated)) { result in
                switch result {
                case .success(let feed):
                    continuation.resume(returning: feed.rssFeed?.items ?? [])
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    @MainActor
    private func loadFeed(showsLoading: Bool = false, resetPagination: Bool = false) async {
        if showsLoading {
            loading = true
        }
        
        if resetPagination {
            requestedItemCount = Self.pageSize
            hasMore = true
        }
        
        defer {
            loading = false
        }
        
        do {
            let feedItems = try await fetchItems(limit: requestedItemCount)
                .map(mapItem)

            dailyFeeds = groupByDate(feedItems)
            hasMore = feedItems.count >= requestedItemCount
            lastUpdatedAt = .now
            loadErrorMessage = nil
            AnalyticsService.logEvent(
                "notification_feed_load",
                parameters: [
                    "status": "success",
                    "limit": requestedItemCount,
                    "item_count": feedItems.count
                ]
            )
        } catch {
            if dailyFeeds.isEmpty {
                loadErrorMessage = "加载失败，请稍后重试"
            } else {
                loadErrorMessage = "更新失败，已显示上次结果"
            }
            AnalyticsService.logEvent(
                "notification_feed_load",
                parameters: [
                    "status": "failed",
                    "limit": requestedItemCount,
                    "error_type": AnalyticsService.errorTypeName(error)
                ]
            )
        }
    }
    
    @MainActor
    private func loadMore() async {
        guard !loadingMore, !loading, hasMore else {
            return
        }
        
        loadingMore = true
        let previousCount = totalFeedCount
        let nextCount = requestedItemCount + Self.pageSize
        
        defer {
            loadingMore = false
        }
        
        do {
            let feedItems = try await fetchItems(limit: nextCount)
                .map(mapItem)
            
            dailyFeeds = groupByDate(feedItems)
            requestedItemCount = nextCount
            hasMore = feedItems.count >= nextCount && feedItems.count > previousCount
            lastUpdatedAt = .now
            loadErrorMessage = nil
            AnalyticsService.logEvent(
                "notification_feed_load_more",
                parameters: [
                    "status": "success",
                    "limit": nextCount,
                    "item_count": feedItems.count
                ]
            )
        } catch {
            loadErrorMessage = "加载更多失败，请稍后重试"
            AnalyticsService.logEvent(
                "notification_feed_load_more",
                parameters: [
                    "status": "failed",
                    "limit": nextCount,
                    "error_type": AnalyticsService.errorTypeName(error)
                ]
            )
        }
    }

    var body: some View {
        ZStack {
            backgroundGradient
            
            if loading, dailyFeeds.isEmpty {
                loadingView
            } else if dailyFeeds.isEmpty {
                emptyStateView
            } else {
                List {
                    ForEach(dailyFeeds, id: \.id) { day in
                        Section {
                            ForEach(day.items) { item in
                                feedCard(item)
                            }
                        } header: {
                            sectionHeader(for: day)
                        }
                        .textCase(nil)
                    }
                    
                    loadMoreFooter
                }
                .listStyle(.plain)
                .listSectionSpacing(10)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await loadFeed(resetPagination: true)
                }
            }
        }
        .sheet(item: $selectedURL) { selectedURL in
            SafariView(url: selectedURL.id)
                .ignoresSafeArea()
        }
        .task {
            await loadFeed(showsLoading: true, resetPagination: true)
        }
        .analyticsScreen(
            "academic_notifications",
            screenClass: "NotificationView",
            parameters: [
                "loaded_count": totalFeedCount
            ]
        )
        .animation(.easeInOut(duration: 0.2), value: loading)
        .animation(.easeInOut(duration: 0.2), value: dailyFeeds.count)
        .navigationTitle("教务通知")
    }
}

private struct NotificationCardButtonStyle: ButtonStyle {
    let enabled: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && enabled ? 0.985 : 1)
            .opacity(configuration.isPressed && enabled ? 0.92 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

#Preview {
    NotificationView()
}
