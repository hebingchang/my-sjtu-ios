//
//  TabView.swift
//  MySJTU
//
//  Created by boar on 2024/09/29.
//

import SwiftUI

struct RootTabView: View {
    let today = Calendar.current.component(.day, from: Date())
    @AppStorage("displayMode") var displayMode: DisplayMode = .day
    @StateObject var qaManager = QuickActionsManager.instance
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject private var appConfig: AppConfig
    
    @State private var isUnicodePresented = false
    @State private var isAccountViewPresent = false
    @State private var selectedTab: Int = 1
    @State private var previousTab: Int = 1
    
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
        //        ZStack(alignment: .bottom) {
        TabView(selection: $selectedTab) {
            Group {
                ScheduleView()
                    .tabItem {
                        Image(systemName: displayMode == .day ? "calendar.day.timeline.left" : "calendar")
                        Text("日程")
                    }
                    .tag(1)
                
                Color.clear
                    .tabItem {
                        Image(systemName: "qrcode")
                        Text("思源码")
                    }
                    .tag(2)
                    .onTapGesture {
                        print("tap unicode")
                    }
                
                ProfileView()
                    .tabItem {
                        Image(systemName: "person.crop.circle.fill")
                        Text("我")
                    }
                    .tag(3)
            }
            .toolbarBackgroundVisibility(.visible, for: .tabBar)
            // .toolbarBackground(.tab, for: .tabBar)
        }
        .onChange(of: selectedTab) {
            if selectedTab == 2 {
                if previousTab == 1 {
                    selectedTab = 1
                } else if previousTab == 3 {
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        selectedTab = 3
                    }
                }
                checkUnicode()
            } else {
                previousTab = selectedTab
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
        
        //            HStack {
        //                VStack(spacing: 4) {
        //                    Image(systemName: displayMode == .day ? "calendar.day.timeline.left" : "calendar")
        //                        .font(.system(size: 24))
        //                    Text("日程")
        //                        .font(.system(size: 9))
        //                }
        //                .foregroundColor(selectedTab == 1 ? Color(UIColor.tintColor) : .gray)
        //                .frame(maxWidth: .infinity)
        //                .contentShape(Rectangle())
        //                .onTapGesture {
        //                    selectedTab = 1
        //                }
        //
        //                VStack(spacing: 4) {
        //                    Image(systemName: "qrcode")
        //                        .font(.system(size: 24))
        //                    Text("思源码")
        //                        .font(.system(size: 9))
        //                }
        //                .foregroundColor(.gray)
        //                .frame(maxWidth: .infinity)
        //                .contentShape(Rectangle())
        //                .onTapGesture {
        //                    checkUnicode()
        //                }
        //
        //                VStack(spacing: 4) {
        //                    Image(systemName: "person.crop.circle.fill")
        //                        .font(.system(size: 24))
        //                    Text("我")
        //                        .font(.system(size: 9))
        //                }
        //                .foregroundColor(selectedTab == 3 ? Color(UIColor.tintColor) : .gray)
        //                .frame(maxWidth: .infinity)
        //                .contentShape(Rectangle())
        //                .onTapGesture {
        //                    if selectedTab == 3 {
        //                    } else {
        //                        selectedTab = 3
        //                    }
        //                }
        //            }
        //            .padding([.top], 7)
        //            .ignoresSafeArea()
    }
    //    }
}

#Preview {
    RootTabView()
        .accentColor(Color(red: 200 / 255, green: 22 / 255, blue: 30 / 255))
}
