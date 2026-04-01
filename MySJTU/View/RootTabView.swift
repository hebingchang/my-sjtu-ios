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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appConfig: AppConfig

    @State private var isUnicodePresented = false
    @State private var isAccountViewPresent = false
    @State private var selectedIndex = 0
    @State private var selectedSidebarItem: SidebarItem? = .schedule
    @State private var sidebarPath: [SidebarDestination] = []
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var busViewModel = BusMapViewModel()
    @State private var busSidebarStation: BusAPI.Station?
    @State private var busSidebarLineDetail: BusLineDetailSelection?

    @State private var showNoAccountAlert: Bool = false
    @State private var showNoPermission: Bool = false
    @State private var inSetting: Bool = false

    enum SidebarItem: Hashable {
        case schedule
        case accounts
        case dataSource
        case customize
        case canvasSettings
        case canvasEvents
        case notifications
        case selfStudyClassroom
        case exams
        case campusCard
        case bus
        case about
    }

    private enum SidebarDestination: Hashable {
        case busSidebar
        case busStation
        case busLineDetail
    }

    private var shouldShowUnicodeTab: Bool {
        appConfig.appStatus == .review ||
        alwaysShowUnicode ||
        accounts.contains(where: { $0.provider == .jaccount && $0.enabledFeatures.contains(.unicode) })
    }

    private var jAccount: WebAuthAccount? {
        accounts.first { $0.provider == .jaccount }
    }

    private var hasCanvasAccess: Bool {
        guard let account = jAccount else { return false }
        return account.enabledFeatures.contains(.canvas) && account.bizData["canvas_token"] != nil
    }

    private var hasExamAccess: Bool {
        jAccount?.enabledFeatures.contains(.examAndGrade) ?? false
    }

    private var hasCampusCardAccess: Bool {
        jAccount?.enabledFeatures.contains(.campusCard) ?? false
    }

    private var homeIconName: String {
        displayMode == .day ? "calendar.day.timeline.left" : "calendar"
    }

    private var busSidebarPresentation: BusSidebarPresentation {
        BusSidebarPresentation(
            station: $busSidebarStation,
            lineDetail: $busSidebarLineDetail,
            showRoot: showBusSidebarRoot,
            showStation: showBusSidebarStation,
            showLineDetail: showBusSidebarLineDetail
        )
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
        Group {
            if horizontalSizeClass == .regular {
                sidebarLayout
            } else {
                tabBarLayout
            }
        }
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
        .onChange(of: selectedSidebarItem) { _, newValue in
            if newValue != .bus, !sidebarPath.isEmpty {
                sidebarPath.removeAll()
            }
            if newValue != .bus {
                resetBusSidebarSelection()
            }
        }
        .onChange(of: sidebarPath) { _, newValue in
            syncBusSidebarSelection(with: newValue)
        }
    }

    // MARK: - iPad Sidebar Layout

    @ViewBuilder
    private var sidebarLayout: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            NavigationStack(path: $sidebarPath) {
                List(selection: $selectedSidebarItem) {
                    Section {
                        Label("日程", systemImage: homeIconName)
                            .tag(SidebarItem.schedule)

                        if shouldShowUnicodeTab {
                            Button {
                                checkUnicode()
                            } label: {
                                Label("思源码", systemImage: "qrcode")
                            }
                        }
                    }

                    if appConfig.appStatus == .normal {
                        Section("设置") {
                            Label("账户", systemImage: "person.crop.circle")
                                .tag(SidebarItem.accounts)
                            Label("数据源", systemImage: "square.and.arrow.down")
                                .tag(SidebarItem.dataSource)
                            Label("个性化", systemImage: "paintpalette")
                                .tag(SidebarItem.customize)
                            if hasCanvasAccess {
                                Label("Canvas 设置", systemImage: "link.circle")
                                    .tag(SidebarItem.canvasSettings)
                            }
                        }
                    }

                    Section("学在交大") {
                        if hasCanvasAccess {
                            Label("Canvas 待办事项", systemImage: "book.pages")
                                .tag(SidebarItem.canvasEvents)
                        }
                        Label("教务通知", systemImage: "megaphone")
                            .tag(SidebarItem.notifications)
                        Label("自习教室", systemImage: "studentdesk")
                            .tag(SidebarItem.selfStudyClassroom)
                        if hasExamAccess {
                            Label("考试与成绩", systemImage: "pencil.and.list.clipboard")
                                .tag(SidebarItem.exams)
                        }
                    }

                    Section("交大生活") {
                        if hasCampusCardAccess {
                            Label("校园卡", systemImage: "person.text.rectangle")
                                .tag(SidebarItem.campusCard)
                        }
                        NavigationLink(value: SidebarDestination.busSidebar) {
                            Label("校园巴士", systemImage: "bus.fill")
                        }
                        .tag(SidebarItem.bus)
                    }

                    Section {
                        Label("关于", systemImage: "info.circle")
                            .tag(SidebarItem.about)
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("交课表")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: SidebarDestination.self) { destination in
                    switch destination {
                    case .busSidebar:
                        BusSidebarRootView()
                            .onAppear {
                                selectedSidebarItem = .bus
                            }
                    case .busStation:
                        if let station = busSidebarStation {
                            BusSidebarStationNavigationView(
                                station: station,
                                viewModel: busViewModel,
                                onSelectLineDetail: showBusSidebarLineDetail
                            )
                        } else {
                            BusSidebarRootView()
                        }
                    case .busLineDetail:
                        if let selection = busSidebarLineDetail {
                            BusSidebarLineDetailNavigationView(
                                selection: selection,
                                viewModel: busViewModel,
                                onSelectDirectionFilter: { mode in
                                    showBusSidebarLineDetail(
                                        selection.updatingDirectionFilter(mode)
                                    )
                                }
                            )
                        } else if let station = busSidebarStation {
                            BusSidebarStationNavigationView(
                                station: station,
                                viewModel: busViewModel,
                                onSelectLineDetail: showBusSidebarLineDetail
                            )
                        } else {
                            BusSidebarRootView()
                        }
                    }
                }
            }
        } detail: {
            sidebarDetailView
        }
    }

    @ViewBuilder
    private var sidebarDetailView: some View {
        switch selectedSidebarItem {
        case .schedule, nil:
            ScheduleView()
                .navigationBarTitleDisplayMode(.inline)
        case .accounts:
            NavigationStack {
                AccountListView()
            }
        case .dataSource:
            NavigationStack {
                DataSourceView()
            }
        case .customize:
            NavigationStack {
                CustomizeView()
            }
        case .canvasSettings:
            NavigationStack {
                CanvasSettingsView()
            }
        case .canvasEvents:
            NavigationStack {
                CanvasEventsView()
            }
        case .notifications:
            NavigationStack {
                NotificationView()
            }
        case .selfStudyClassroom:
            NavigationStack {
                SelfStudyClassroomView()
            }
        case .exams:
            NavigationStack {
                ExamView()
            }
        case .campusCard:
            NavigationStack {
                CampusCardListView()
            }
        case .bus:
            NavigationStack {
                BusListView(
                    sidebarPresentation: busSidebarPresentation,
                    viewModel: busViewModel
                )
            }
        case .about:
            NavigationStack {
                AboutView()
            }
        }
    }

    // MARK: - iPhone Tab Bar Layout

    @ViewBuilder
    private var tabBarLayout: some View {
        NativeTabBarController(
            selectedIndex: $selectedIndex,
            displayMode: displayMode,
            showsUnicodeTab: shouldShowUnicodeTab
        ) {
            checkUnicode()
        }
        .ignoresSafeArea()
    }

    private func showBusSidebarRoot() {
        expandSidebarIfNeeded()
        selectedSidebarItem = .bus
        resetBusSidebarSelection()
        sidebarPath = [.busSidebar]
    }

    private func showBusSidebarStation(
        _ station: BusAPI.Station
    ) {
        expandSidebarIfNeeded()
        selectedSidebarItem = .bus
        busSidebarStation = station
        busSidebarLineDetail = nil
        sidebarPath = [.busSidebar, .busStation]
    }

    private func showBusSidebarLineDetail(
        _ selection: BusLineDetailSelection
    ) {
        expandSidebarIfNeeded()
        selectedSidebarItem = .bus
        busSidebarStation = selection.station
        busSidebarLineDetail = selection
        sidebarPath = [.busSidebar, .busStation, .busLineDetail]
    }

    private func resetBusSidebarSelection() {
        busSidebarStation = nil
        busSidebarLineDetail = nil
    }

    private func syncBusSidebarSelection(
        with path: [SidebarDestination]
    ) {
        guard selectedSidebarItem == .bus else {
            return
        }

        if !path.contains(.busLineDetail) {
            busSidebarLineDetail = nil
        }

        if !path.contains(.busStation) {
            busSidebarStation = nil
        }
    }

    private func expandSidebarIfNeeded() {
        guard sidebarVisibility != .all else {
            return
        }

        sidebarVisibility = .all
    }
}

#Preview {
    RootTabView()
        .accentColor(Color(red: 200 / 255, green: 22 / 255, blue: 30 / 255))
}
