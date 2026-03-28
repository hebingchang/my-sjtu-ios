//
//  WatchMoreView.swift
//  MySJTUWatch Watch App
//
//  Created by boar on 2026/03/27.
//

import SwiftUI

struct WatchMoreView: View {
    @EnvironmentObject private var store: WatchScheduleStore

    var body: some View {
        List {
            Section {
                Button("从 iPhone 同步课表") {
                    store.requestRefreshIfPossible()
                }
                .disabled(!store.isReachable)
            }

            Section {
                NavigationLink("关于") {
                    WatchAboutView(snapshot: store.snapshot)
                }
            }
        }
        .navigationTitle("更多")
    }
}

private struct WatchAboutView: View {
    let snapshot: WatchScheduleSnapshot?

    private var versionText: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersion) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("交课表 Watch")
                        .font(.headline)

                    Text("专注于在手表上快速查看日程的交大课表。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)

            Section("版本") {
                LabeledContent("应用版本", value: versionText)
            }

            if let snapshot {
                Section {
                    LabeledContent("数据源", value: snapshot.sourceName)
                } header: {
                    Text("同步")
                } footer: {
                    Text("日程内容来自 iPhone 上最近一次同步。\n\n首次使用时，请先在 iPhone 上打开交课表并完成日程导入。之后手表会自动接收最近一次同步的日程快照。")
                }
            }
        }
        .navigationTitle("关于")
    }
}
