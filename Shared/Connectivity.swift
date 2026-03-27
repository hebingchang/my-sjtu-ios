//
//  Connectivity.swift
//  MySJTU
//
//  Created by boar on 2024/12/18.
//

import Foundation
import WatchConnectivity

final class Connectivity: NSObject, ObservableObject {
    static let shared = Connectivity()
    
    override private init() {
        super.init()
#if !os(watchOS)
        guard WCSession.isSupported() else {
            return
        }
#endif
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    
    public func send(collegeId: College) {
        guard WCSession.default.activationState == .activated else {
            return
        }
        
#if os(watchOS)
        guard WCSession.default.isCompanionAppInstalled else {
            return
        }
#else
        guard WCSession.default.isWatchAppInstalled else {
            return
        }
#endif
    }
}

// MARK: - WCSessionDelegate
extension Connectivity: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
    }
    
#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        // If the person has more than one watch, and they switch,
        // reactivate their session on the new device.
        WCSession.default.activate()
    }
#endif
}
