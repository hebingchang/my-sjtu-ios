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
    @StateObject var progressor: Progressor = Progressor()
    @StateObject var appConfig: AppConfig = AppConfig(appStatus: .normal)
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
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(progressor)
                .environmentObject(appConfig)
                .onAppear {
                    UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(named: "AccentColor")
                }
                .task {
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
                        }
                    }
                }
                .overlay {
                    ProgressOverlay(isShowingProgress: progressor.isShowingProgress, progress: progressor.progress)
                        .animation(.easeInOut, value: progressor.isShowingProgress)
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
                                let shsmuSemesters = try await getSemesters(college: .shsmu)
                                
                                try await pool.write { db in
                                    do {
                                        try (sjtuSemesters + sjtugSemesters + shsmuSemesters).forEach { semester in
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
        }
        .databaseContext(.readWrite {
            guard let pool = Eloquent.pool else {
                throw EloquentError.dbNotOpened
            }
            
            return pool
        })
    }
}

#if DEBUG
extension UIViewController {
    @objc func injected() {
        viewDidLoad()
    }
}
#endif
