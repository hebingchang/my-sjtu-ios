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
    @AppStorage("accounts") private var analyticsAccounts: [WebAuthAccount] = []
    @AppStorage("displayMode") private var analyticsDisplayMode: DisplayMode = .day
    @AppStorage("aiConfig") private var analyticsAIConfig = AIConfig()

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
                            _ = try await AIService.refreshChatSJTUToken(cookies: jAccount.cookies)
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
            rootContent
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

    private var rootContent: some View {
        RootTabView(aiChatViewModel: aiChatViewModel)
            .environmentObject(progressor)
            .environmentObject(appConfig)
            .environmentObject(toolNotificationAlertCenter)
            .onAppear(perform: handleAppear)
            .overlay {
                ProgressOverlay(isShowingProgress: progressor.isShowingProgress, progress: progressor.progress)
                    .animation(.easeInOut, value: progressor.isShowingProgress)
            }
            .task {
                await runInitialTasks()
            }
            .onChange(of: scenePhase) { _, newScenePhase in
                handleScenePhaseChange(newScenePhase)
            }
            .onChange(of: networkMonitor.isConnected) { _, isConnected in
                handleConnectivityChange(isConnected)
            }
            .onChange(of: analyticsAccounts.rawValue) { _, _ in
                syncAnalyticsUserContext()
            }
            .onChange(of: analyticsDisplayMode) { _, _ in
                syncAnalyticsUserContext()
            }
            .onChange(of: analyticsAIConfig.rawValue) { _, _ in
                syncAnalyticsUserContext()
            }
            .onChange(of: appConfig.appStatus) { _, _ in
                syncAnalyticsUserContext()
            }
            .alert(item: $toolNotificationAlertCenter.activeAlert, content: makeAlert)
    }

    private func handleAppear() {
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(named: "AccentColor")
        syncAnalyticsUserContext()
    }

    private func runInitialTasks() async {
        Connectivity.shared.sendLatestScheduleSnapshot()
        await ToolNotificationService.shared.cleanupExpiredPersistedNotifications()
    }

    private func handleScenePhaseChange(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            AnalyticsService.logEvent("app_became_active")
            Connectivity.shared.sendLatestScheduleSnapshot()
            Task {
                await ToolNotificationService.shared.cleanupExpiredPersistedNotifications()
            }
        case .background:
            AnalyticsService.logEvent("app_entered_bg")
        default:
            break
        }
    }

    private func handleConnectivityChange(_ isConnected: Bool) {
        guard isConnected else {
            return
        }

        AnalyticsService.logEvent("network_recovered")
        Task {
            await refreshAppStatus()
        }
        Task(priority: .background) {
            await refreshSemesters()
        }
    }

    private func syncAnalyticsUserContext() {
        AnalyticsService.syncUserContext(
            accounts: analyticsAccounts,
            appStatus: appConfig.appStatus,
            displayMode: analyticsDisplayMode,
            aiConfig: analyticsAIConfig
        )
    }

    private func refreshAppStatus() async {
        do {
            let status = try await getAppStatus()
            appConfig.appStatus = status
        } catch {
            print(error)
        }
    }

    private func refreshSemesters() async {
        do {
            guard let pool = Eloquent.pool else {
                throw EloquentError.dbNotOpened
            }

            let semestersToPersist = try await fetchSemestersForPersistence()
            try await pool.write { db in
                do {
                    try semestersToPersist.forEach { semester in
                        try semester.save(db)
                    }
                } catch {}
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print(error)
        }
    }

    private func fetchSemestersForPersistence() async throws -> [Semester] {
        let sjtuSemesters = try await getSemesters(college: .sjtu)
        let sjtugSemesters = sjtuSemesters.map { semester -> Semester in
            var copiedSemester = semester
            copiedSemester.college = .sjtug
            return copiedSemester
        }
        let jointSemesters = try await getSemesters(college: .joint)
        let shsmuSemesters = try await getSemesters(college: .shsmu)

        return sjtuSemesters + sjtugSemesters + jointSemesters + shsmuSemesters
    }

    private func makeAlert(_ alert: PresentedToolNotificationAlert) -> Alert {
        Alert(
            title: Text(alert.title),
            message: Text(alert.body),
            dismissButton: .default(Text("知道了")) {
                toolNotificationAlertCenter.dismiss()
            }
        )
    }
}

#if DEBUG
extension UIViewController {
    @objc func injected() {
        viewDidLoad()
    }
}
#endif
