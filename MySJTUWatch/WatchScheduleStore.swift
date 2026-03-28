//
//  WatchScheduleStore.swift
//  MySJTUWatch Watch App
//
//  Created by boar on 2026/03/27.
//

import Foundation
import Combine
import WatchConnectivity

struct WatchScheduleSnapshot: Codable, Equatable {
    let generatedAt: Date
    let sourceName: String
    let days: [WatchScheduleDaySnapshot]
}

struct WatchScheduleDaySnapshot: Codable, Equatable, Identifiable {
    let date: Date
    let items: [WatchScheduleItemSnapshot]

    var id: Date {
        date
    }
}

struct WatchScheduleItemSnapshot: Codable, Equatable, Identifiable {
    let id: String
    let kind: WatchScheduleItemKind
    let title: String
    let subtitle: String
    let startAt: Date
    let endAt: Date
    let colorHex: String
}

enum WatchScheduleItemKind: String, Codable {
    case course
    case custom
}

private enum WatchScheduleSyncPayload {
    static let snapshotKey = "watch.schedule.snapshot"
    static let refreshCommand = "watch.schedule.refresh"
    static let cachedSnapshotKey = "watch.schedule.cachedSnapshot"
}

@MainActor
final class WatchScheduleStore: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchScheduleSnapshot?
    @Published private(set) var isCompanionAppInstalled = false
    @Published private(set) var isReachable = false

    override init() {
        super.init()
        loadCachedSnapshot()
        activateSessionIfPossible()
    }

    init(previewSnapshot: WatchScheduleSnapshot) {
        self.snapshot = previewSnapshot
        self.isCompanionAppInstalled = true
        self.isReachable = true
        super.init()
    }

    func requestRefreshIfPossible() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            return
        }

        guard session.isReachable else {
            return
        }

        session.sendMessage([WatchScheduleSyncPayload.refreshCommand: true], replyHandler: nil) { error in
            print("Watch refresh request failed: \(error)")
        }
    }

    private func activateSessionIfPossible() {
        guard WCSession.isSupported() else {
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
        refreshSessionState()
    }

    private func refreshSessionState() {
        let session = WCSession.default
        isCompanionAppInstalled = session.isCompanionAppInstalled
        isReachable = session.isReachable
    }

    private func apply(applicationContext: [String: Any]) {
        guard let payload = applicationContext[WatchScheduleSyncPayload.snapshotKey] as? Data else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        do {
            let snapshot = try decoder.decode(WatchScheduleSnapshot.self, from: payload)
            self.snapshot = snapshot
            UserDefaults.standard.set(payload, forKey: WatchScheduleSyncPayload.cachedSnapshotKey)
        } catch {
            print("Watch snapshot decode failed: \(error)")
        }
    }

    private func loadCachedSnapshot() {
        guard let payload = UserDefaults.standard.data(forKey: WatchScheduleSyncPayload.cachedSnapshotKey) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        snapshot = try? decoder.decode(WatchScheduleSnapshot.self, from: payload)
    }
}

extension WatchScheduleStore: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            refreshSessionState()
            apply(applicationContext: session.receivedApplicationContext)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshSessionState()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            apply(applicationContext: applicationContext)
        }
    }
}

extension WatchScheduleStore {
    static var preview: WatchScheduleStore {
        let startOfToday = Date.now.watchScheduleDay
        return WatchScheduleStore(
            previewSnapshot: WatchScheduleSnapshot(
                generatedAt: Date.now,
                sourceName: "本科 + 研究生",
                days: [
                    WatchScheduleDaySnapshot(
                        date: startOfToday,
                        items: [
                            WatchScheduleItemSnapshot(
                                id: "preview-course-1",
                                kind: .course,
                                title: "高等数学",
                                subtitle: "本科 · 上院 103",
                                startAt: startOfToday.addingTimeInterval(8 * 3600),
                                endAt: startOfToday.addingTimeInterval(9.5 * 3600),
                                colorHex: "#336774"
                            ),
                            WatchScheduleItemSnapshot(
                                id: "preview-course-2",
                                kind: .custom,
                                title: "组会",
                                subtitle: "研究生 · 软件楼 B201",
                                startAt: startOfToday.addingTimeInterval(14 * 3600),
                                endAt: startOfToday.addingTimeInterval(15 * 3600),
                                colorHex: "#CB1B45"
                            )
                        ]
                    ),
                    WatchScheduleDaySnapshot(
                        date: startOfToday.addingTimeInterval(24 * 3600),
                        items: []
                    )
                ]
            )
        )
    }
}
