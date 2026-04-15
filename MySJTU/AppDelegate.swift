//
//  AppDelegate.swift
//  MySJTU
//
//  Created by boar on 2024/11/25.
//

import Foundation
import UIKit
import UserNotifications
import FirebaseCore

class QuickActionsManager: ObservableObject {
    static let instance = QuickActionsManager()
    @Published var quickAction: QuickAction? = nil

    func handleQaItem(_ item: UIApplicationShortcutItem) {
        if item.type == "UnicodeAction" {
            quickAction = .unicode
        }
    }
}

enum QuickAction: Hashable {
    case unicode
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        AnalyticsService.configure()
        AnalyticsService.logEvent(
            "session_started",
            parameters: [
                "launch_source": launchOptions?[.shortcutItem] == nil ? "default" : "shortcut"
            ]
        )
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem {
            QuickActionsManager.instance.handleQaItem(shortcutItem)
        }

        let sceneConfiguration = UISceneConfiguration(name: "Custom Configuration", sessionRole: connectingSceneSession.role)
        sceneConfiguration.delegateClass = CustomSceneDelegate.self

        return sceneConfiguration
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        CanvasVideoOrientationController.currentMask
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if ToolNotificationService.isManagedNotification(notification) {
            completionHandler([])
            Task {
                await ToolNotificationService.shared.handleTriggeredNotification(notification)
            }
            return
        }

        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task {
            await ToolNotificationService.shared.handleTriggeredNotification(
                response.notification
            )
            completionHandler()
        }
    }
}

class CustomSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        QuickActionsManager.instance.handleQaItem(shortcutItem)
    }
}
