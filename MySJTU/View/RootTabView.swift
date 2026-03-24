//
//  TabView.swift
//  MySJTU
//
//  Created by boar on 2024/09/29.
//

import SwiftUI
import UIKit

struct NativeTabBarController: UIViewControllerRepresentable {
    fileprivate enum TabIndex: Int {
        case home = 0
        case unicode = 1
        case profile = 2
    }

    @Binding var selectedIndex: Int
    var displayMode: DisplayMode
    var showsUnicodeTab: Bool
    var onActionTap: () -> Void

    private var homeIconName: String {
        displayMode == .day ? "calendar.day.timeline.left" : "calendar"
    }

    private var visibleTabs: [TabIndex] {
        showsUnicodeTab ? [.home, .unicode, .profile] : [.home, .profile]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UITabBarController {
        let tab = UITabBarController()
        tab.delegate = context.coordinator

        tab.viewControllers = context.coordinator.viewControllers(for: visibleTabs)
        tab.selectedIndex = visibleIndex(for: normalizedSelection(preferred: selectedIndex, fallback: nil))

        return tab
    }

    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {
        context.coordinator.parent = self

        let currentLogicalSelection = currentTabIndex(in: uiViewController)
        let normalizedSelection = normalizedSelection(
            preferred: selectedIndex,
            fallback: currentLogicalSelection
        )

        if currentLogicalSelection?.rawValue != normalizedSelection {
            context.coordinator.updateSelectedIndex(to: normalizedSelection)
        }

        if currentTabOrder(in: uiViewController) != visibleTabs {
            uiViewController.setViewControllers(
                context.coordinator.viewControllers(for: visibleTabs),
                animated: false
            )
        }

        let targetVisibleIndex = visibleIndex(for: normalizedSelection)
        if uiViewController.selectedIndex != targetVisibleIndex {
            uiViewController.selectedIndex = targetVisibleIndex
        }

        context.coordinator.updateHomeTabBarItem(iconName: homeIconName)
    }

    private func normalizedSelection(preferred: Int, fallback: TabIndex?) -> Int {
        if visibleTabs.contains(where: { $0.rawValue == preferred }) {
            return preferred
        }

        if let fallback, visibleTabs.contains(fallback) {
            return fallback.rawValue
        }

        return TabIndex.home.rawValue
    }

    private func visibleIndex(for logicalIndex: Int) -> Int {
        visibleTabs.firstIndex(where: { $0.rawValue == logicalIndex }) ?? 0
    }

    private func currentTabOrder(in tabBarController: UITabBarController) -> [TabIndex] {
        tabBarController.viewControllers?.compactMap {
            TabIndex(rawValue: $0.tabBarItem.tag)
        } ?? []
    }

    private func currentTabIndex(in tabBarController: UITabBarController) -> TabIndex? {
        guard let selectedViewController = tabBarController.selectedViewController else {
            return nil
        }

        return TabIndex(rawValue: selectedViewController.tabBarItem.tag)
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var parent: NativeTabBarController
        private lazy var cachedHomeController = parent.homeController()
        private lazy var cachedUnicodeController = parent.unicodeController()
        private lazy var cachedProfileController = parent.profileController()
        private var currentHomeIconName: String?

        init(parent: NativeTabBarController) {
            self.parent = parent
        }

        fileprivate func viewControllers(for tabs: [TabIndex]) -> [UIViewController] {
            tabs.map { tab in
                switch tab {
                case .home:
                    cachedHomeController
                case .unicode:
                    cachedUnicodeController
                case .profile:
                    cachedProfileController
                }
            }
        }

        func updateHomeTabBarItem(iconName: String) {
            guard currentHomeIconName != iconName,
                  let homeTabBarItem = cachedHomeController.tabBarItem else {
                return
            }

            homeTabBarItem.image = UIImage(systemName: iconName)
            homeTabBarItem.selectedImage = nil
            currentHomeIconName = iconName
        }

        func tabBarController(_ tabBarController: UITabBarController,
                              shouldSelect viewController: UIViewController) -> Bool {
            if viewController.tabBarItem.tag == TabIndex.unicode.rawValue {
                parent.onActionTap()
                return false
            }
            return true
        }

        func tabBarController(_ tabBarController: UITabBarController,
                              didSelect viewController: UIViewController) {
            updateSelectedIndex(to: viewController.tabBarItem.tag)
        }

        func updateSelectedIndex(to logicalIndex: Int) {
            guard parent.selectedIndex != logicalIndex else {
                return
            }

            DispatchQueue.main.async {
                self.parent.selectedIndex = logicalIndex
            }
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
    @AppStorage("accounts") private var accounts: [WebAuthAccount] = []
    @AppStorage("settings.always_show_unicode_in_tabbar") private var alwaysShowUnicode: Bool = true
    @StateObject var qaManager = QuickActionsManager.instance
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject private var appConfig: AppConfig
    
    @State private var isUnicodePresented = false
    @State private var isAccountViewPresent = false
    @State private var selectedIndex = 0
    
    @State private var showNoAccountAlert: Bool = false
    @State private var showNoPermission: Bool = false
    @State private var inSetting: Bool = false

    private var shouldShowUnicodeTab: Bool {
        appConfig.appStatus == .review ||
        alwaysShowUnicode ||
        accounts.contains(where: { $0.provider == .jaccount && $0.enabledFeatures.contains(.unicode) })
    }
    
    private func checkUnicode(alert: Bool = true) {
        if appConfig.appStatus == .review {
            isUnicodePresented = true
            return
        }

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
    }
    
    var body: some View {
        NativeTabBarController(
            selectedIndex: $selectedIndex,
            displayMode: displayMode,
            showsUnicodeTab: shouldShowUnicodeTab
        ) {
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
