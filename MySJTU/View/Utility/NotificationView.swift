//
//  NotificationView.swift
//  MySJTU
//
//  Created by 何炳昌 on 2024/12/13.
//

import SwiftUI
import FeedKit
import Collections
import SafariServices

struct NotificationView: View {
    @State private var loading: Bool = true
    @State private var feedGroup: OrderedDictionary<String, [RSSFeedItem]> = [:]
    @State private var dailyFeeds: [DailyFeeds] = []
        
    private struct DailyFeeds {
        let date: String
        let items: [RSSFeedItem]
    }

    private struct IdentifiableURL: Identifiable {
        public var id: URL
    }

    private func openSafariView(url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return
        }

        let safariVC = SFSafariViewController(url: url)
        safariVC.modalPresentationStyle = .fullScreen // Ensures it covers the TabView
        keyWindow.rootViewController?.present(safariVC, animated: true, completion: nil)
    }
    
    private func loadFeed() async throws {
        let feedURL = URL(string: "https://jwc.sjtu.edu.cn/system/resource/code/rss/rssfeed.jsp?type=list&treeid=1292&viewid=1011878&mode=10&dbname=vsb&owner=1707467176&ownername=jwc2021&contentid=1015253&number=20&httproot=")!
        let parser = FeedParser(URL: feedURL)
        parser.parseAsync(queue: DispatchQueue.global(qos: .userInitiated)) { result in
            switch result {
            case .success(let feed):
                var feeds: [DailyFeeds] = []
                for (date, items) in OrderedDictionary(grouping: feed.rssFeed?.items ?? [], by: { $0.pubDate?.formattedMonthDay(format: "M/d") ?? "" }) {
                    feeds.append(DailyFeeds(date: date, items: items))
                }
                self.dailyFeeds = feeds
            case .failure(_):
                break
            }
            DispatchQueue.main.async {
                loading = false
            }
        }
    }

    var body: some View {
        ZStack {
            if loading {
                VStack {
                    ProgressView()
                }
            } else {
                List {
                    ForEach(dailyFeeds, id: \.date) { day in
                        Section(header: Text(day.date)) {
                            ForEach(day.items, id: \.guid!.value) { item in
                                Button {
                                    if let link = item.link {
                                        openSafariView(url: URL(string: link)!)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title ?? "")
                                            .foregroundStyle(Color(UIColor.label))
                                            .fontWeight(.medium)
                                        Text(item.description ?? "")
                                            .foregroundStyle(Color(UIColor.secondaryLabel))
                                            .font(.callout)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    do {
                        try await Task.sleep(for: .seconds(1))
                        try await loadFeed()
                    } catch {}
                }
            }
        }
        .task {
            do {
                try await loadFeed()
            } catch {}
        }
        .animation(.easeInOut, value: loading)
        .navigationTitle("教务通知")
    }
}

#Preview {
    NotificationView()
}
