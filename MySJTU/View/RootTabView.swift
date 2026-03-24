//
//  TabView.swift
//  MySJTU
//
//  Created by boar on 2024/09/29.
//

import SwiftUI
import UIKit

struct NativeTabBarController: UIViewControllerRepresentable {
    private enum TabIndex: Int {
        case home = 0
        case unicode = 1
        case profile = 2
    }

    @Binding var selectedIndex: Int
    var displayMode: DisplayMode
    var onActionTap: () -> Void

    private var homeIconName: String {
        displayMode == .day ? "calendar.day.timeline.left" : "calendar"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let tab = UITabBarController()
        tab.delegate = context.coordinator

        tab.viewControllers = [
            homeController(),
            unicodeController(),
            profileController(),
        ]
        tab.selectedIndex = selectedIndex

        return tab
    }

    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {
        if uiViewController.selectedIndex != selectedIndex {
            uiViewController.selectedIndex = selectedIndex
        }

        if let viewControllers = uiViewController.viewControllers,
           viewControllers.indices.contains(TabIndex.home.rawValue) {
            let homeTabBarItem = viewControllers[TabIndex.home.rawValue].tabBarItem
            if homeTabBarItem?.accessibilityIdentifier != homeIconName {
                homeTabBarItem?.image = UIImage(systemName: homeIconName)
                homeTabBarItem?.selectedImage = nil
                homeTabBarItem?.accessibilityIdentifier = homeIconName
            }
        }
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var parent: NativeTabBarController

        init(parent: NativeTabBarController) {
            self.parent = parent
        }

        func tabBarController(_ tabBarController: UITabBarController,
                              shouldSelect viewController: UIViewController) -> Bool {
            guard
                let vcs = tabBarController.viewControllers,
                let index = vcs.firstIndex(of: viewController)
            else { return true }

            if index == TabIndex.unicode.rawValue {
                parent.onActionTap()
                return false
            }
            return true
        }

        func tabBarController(_ tabBarController: UITabBarController,
                              didSelect viewController: UIViewController) {
            parent.selectedIndex = tabBarController.selectedIndex
        }
    }

    private func homeController() -> UIViewController {
        let home = UIHostingController(rootView: ScheduleView())
        let homeTabBarItem = UITabBarItem(
            title: "日程",
            image: UIImage(systemName: homeIconName),
            tag: TabIndex.home.rawValue
        )
        homeTabBarItem.accessibilityIdentifier = homeIconName
        home.tabBarItem = homeTabBarItem
        return home
    }

    private func unicodeController() -> UIViewController {
        let unicode = UIViewController()
        unicode.tabBarItem = UITabBarItem(
            title: "思源码",
            image: UIImage(systemName: "qrcode"),
            tag: TabIndex.unicode.rawValue
        )
        return unicode
    }

    private func profileController() -> UIViewController {
        let profile = UIHostingController(rootView: ProfileView())
        profile.tabBarItem = UITabBarItem(
            title: "我",
            image: UIImage(systemName: "person.crop.circle.fill"),
            tag: TabIndex.profile.rawValue
        )
        return profile
    }
}

struct RootTabView: View {
    let today = Calendar.current.component(.day, from: Date())
    @AppStorage("displayMode") var displayMode: DisplayMode = .day
    @StateObject var qaManager = QuickActionsManager.instance
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject private var appConfig: AppConfig
    
    @State private var isUnicodePresented = false
    @State private var isAccountViewPresent = false
    @State private var selectedIndex = 0
    
    @State private var showNoAccountAlert: Bool = false
    @State private var showNoPermission: Bool = false
    @State private var inSetting: Bool = false
    
    private func checkUnicode(alert: Bool = true) {
        if appConfig.appStatus == .review {
            isUnicodePresented = true
            return
        }
        
        let rawAccounts = UserDefaults.standard.string(forKey: "accounts")
        if let rawAccounts {
            if let accounts = Array<WebAuthAccount>(rawValue: rawAccounts) {
                if let sjtuAccount = accounts.first(where: { $0.provider == .jaccount }) {
                    if sjtuAccount.enabledFeatures.contains(.unicode) {
                        isUnicodePresented = true
                    } else if alert {
                        inSetting = true
                        showNoPermission = true
                    }
                } else if alert {
                    inSetting = true
                    showNoAccountAlert = true
                }
            } else if alert {
                inSetting = true
                showNoAccountAlert = true
            }
        } else if alert {
            inSetting = true
            showNoAccountAlert = true
        }
    }
    
    var body: some View {
        NativeTabBarController(selectedIndex: $selectedIndex, displayMode: displayMode) {
            checkUnicode()
        }
        .ignoresSafeArea()
        .sheet(isPresented: $isUnicodePresented) {
            UnicodeView()
        }
        .sheet(isPresented: $isAccountViewPresent) {
            AccountView(provider: .jaccount)
                .navigationTitle("jAccount 账户")
                .navigationBarTitleDisplayMode(.inline)
        }
        .alert(
            "暂时无法使用思源码",
            isPresented: $showNoAccountAlert
        ) {
            Button {
                isAccountViewPresent = true
            } label: {
                Text("现在登录")
            }
            Button("以后", role: .cancel) {
                showNoAccountAlert = false
            }
        } message: {
            Text("您还没有登录 jAccount 账号。")
        }
        .alert(
            "暂时无法使用思源码",
            isPresented: $showNoPermission
        ) {
            Button {
                isAccountViewPresent = true
            } label: {
                Text("前往设置")
            }
            Button("以后", role: .cancel) {
                showNoPermission = false
            }
        } message: {
            Text("您已经登录了 jAccount 账号，但是没有授权使用思源码。")
        }
        .onChange(of: isAccountViewPresent) {
            if inSetting && !isAccountViewPresent {
                inSetting = false
                checkUnicode(alert: false)
            }
        }
        .task {
            if qaManager.quickAction == .unicode {
                qaManager.quickAction = nil
                checkUnicode()
            }
        }
        .onChange(of: scenePhase) {
            if qaManager.quickAction == .unicode {
                qaManager.quickAction = nil
                checkUnicode()
            }
        }
    }
}

#Preview {
    RootTabView()
        .accentColor(Color(red: 200 / 255, green: 22 / 255, blue: 30 / 255))
}
