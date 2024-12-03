//
//  AppDelegate.swift
//  MySJTU
//
//  Created by boar on 2024/11/25.
//

import Foundation
import UIKit

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

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem {
            QuickActionsManager.instance.handleQaItem(shortcutItem)
        }

        let sceneConfiguration = UISceneConfiguration(name: "Custom Configuration", sessionRole: connectingSceneSession.role)
        sceneConfiguration.delegateClass = CustomSceneDelegate.self

        return sceneConfiguration
    }
}

class CustomSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        QuickActionsManager.instance.handleQaItem(shortcutItem)
    }
}
