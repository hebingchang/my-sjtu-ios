//
//  Connectivity.swift
//  MySJTU
//
//  Created by boar on 2024/12/18.
//

import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity

@MainActor
final class Connectivity: NSObject, ObservableObject {
    static let shared = Connectivity()

    override private init() {
        super.init()
        activateSessionIfPossible()
    }

    func sendLatestScheduleSnapshot() {
        Task {
            await pushLatestScheduleSnapshot()
        }
    }

    private func activateSessionIfPossible() {
        guard WCSession.isSupported() else {
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func pushLatestScheduleSnapshot() async {
        let session = WCSession.default

        guard session.activationState == .activated else {
            return
        }

        guard session.isWatchAppInstalled else {
            return
        }

        do {
            let payload = try WatchScheduleSnapshotBuilder.makePayloadData()
            try session.updateApplicationContext([
                WatchScheduleSyncPayload.snapshotKey: payload
            ])
        } catch {
            print("Watch schedule sync failed: \(error)")
        }
    }
}

extension Connectivity: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard error == nil, activationState == .activated else {
            return
        }

        sendLatestScheduleSnapshot()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[WatchScheduleSyncPayload.refreshCommand] != nil else {
            return
        }

        sendLatestScheduleSnapshot()
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        sendLatestScheduleSnapshot()
    }
#endif
}
#else
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()

    private init() {
    }

    func sendLatestScheduleSnapshot() {
    }
}
#endif
