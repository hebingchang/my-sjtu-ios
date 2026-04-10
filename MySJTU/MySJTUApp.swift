//
//  MySJTUApp.swift
//  MySJTU
//
//  Created by boar on 2024/09/28.
//

import SwiftUI
import WidgetKit

@main
struct MySJTUApp: App {    
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var progressor: Progressor = Progressor()
    @StateObject var appConfig: AppConfig = AppConfig(appStatus: .normal)
    @StateObject private var aiChatViewModel = AIChatViewModel(config: Self.initialAIConfig())
    @StateObject private var toolNotificationAlertCenter = ToolNotificationAlertCenter.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var networkMonitor = NetworkMonitor()

    init() {
//        #if DEBUG
//        Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/iOSInjection.bundle")?.load()
//        #endif

        do {
            try Eloquent.initReadWrite()
            try Eloquent.migrate()
        } catch {
            print(error)
        }

        _ = Connectivity.shared

        Task {
            let rawAccounts = UserDefaults.standard.string(forKey: "accounts")
            if let rawAccounts {
                if var accounts = Array<WebAuthAccount>(rawValue: rawAccounts) {
                    for i in 0..<accounts.count {
                        do {
                            accounts[i] = try await accounts[i].refreshSession()
                        } catch {
                            print(error)
                        }
                    }
                    UserDefaults.standard.set(accounts.rawValue, forKey: "accounts")

                    if let configRaw = UserDefaults.standard.string(forKey: "aiConfig"),
                       let config = AIConfig(rawValue: configRaw),
                       config.isEnabled,
                       config.provider == .chatSJTU,
                       let jAccount = accounts.first(where: { $0.provider == .jaccount && $0.status == .connected }) {
                        do {
                            try await AIService.refreshChatSJTUToken(cookies: jAccount.cookies)
                        } catch {
                            print("AI token refresh failed: \(error)")
                        }
                    }
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(aiChatViewModel: aiChatViewModel)
                .environmentObject(progressor)
                .environmentObject(appConfig)
                .environmentObject(toolNotificationAlertCenter)
                .onAppear {
                    UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(named: "AccentColor")
                }
                .overlay {
                    ProgressOverlay(isShowingProgress: progressor.isShowingProgress, progress: progressor.progress)
                        .animation(.easeInOut, value: progressor.isShowingProgress)
                }
                .task {
                    Connectivity.shared.sendLatestScheduleSnapshot()
                    await ToolNotificationService.shared.cleanupExpiredPersistedNotifications()
                }
                .onChange(of: scenePhase) {
                    if scenePhase == .active {
                        Connectivity.shared.sendLatestScheduleSnapshot()
                        Task {
                            await ToolNotificationService.shared.cleanupExpiredPersistedNotifications()
                        }
                    }
                }
                .onChange(of: networkMonitor.isConnected) {
                    if networkMonitor.isConnected {                        
                        Task {
                            do {
                                let status = try await getAppStatus()
                                appConfig.appStatus = status
                            } catch {
                                print(error)
                            }
                        }
                        
                        Task(priority: .background) {
                            do {
                                guard let pool = Eloquent.pool else {
                                    throw EloquentError.dbNotOpened
                                }
                                
                                let sjtuSemesters = try await getSemesters(college: .sjtu)
                                let sjtugSemesters = sjtuSemesters.map {
                                    var semester = $0
                                    semester.college = .sjtug
                                    return semester
                                }
                                let jointSemesters = try await getSemesters(college: .joint)
                                let shsmuSemesters = try await getSemesters(college: .shsmu)
                                
                                try await pool.write { db in
                                    do {
                                        try (sjtuSemesters + sjtugSemesters + jointSemesters + shsmuSemesters).forEach { semester in
                                            try semester.save(db)
                                        }
                                    } catch {}
                                }
                                WidgetCenter.shared.reloadAllTimelines()
                            } catch {
                                print(error)
                            }
                        }
                    }
                }
                .alert(item: $toolNotificationAlertCenter.activeAlert) { alert in
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.body),
                        dismissButton: .default(Text("知道了")) {
                            toolNotificationAlertCenter.dismiss()
                        }
                    )
                }
        }
        .databaseContext(.readWrite {
            guard let pool = Eloquent.pool else {
                throw EloquentError.dbNotOpened
            }
            
            return pool
        })
    }

    private static func initialAIConfig() -> AIConfig {
        guard let rawValue = UserDefaults.standard.string(forKey: "aiConfig"),
              let config = AIConfig(rawValue: rawValue) else {
            return AIConfig()
        }

        return config
    }
}

#if DEBUG
extension UIViewController {
    @objc func injected() {
        viewDidLoad()
    }
}
#endif
