//
//  ProfileView.swift
//  MySJTU
//
//  Created by boar on 2024/09/28.
//

import SwiftUI

struct CollegeItem: Identifiable {
    let id: College
    let name: String
}

struct ProfileView: View {
    @EnvironmentObject private var appConfig: AppConfig
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @State private var hideTabBar: Bool = false

    var body: some View {
        NavigationStack {
            List {
                if appConfig.appStatus == .normal {
                    Section(header: Text("设置")) {
                        NavigationLink {
                            AccountListView()
                        } label: {
                            Label("账户", systemImage: "person.crop.circle")
                        }
                        
                        NavigationLink {
                            DataSourceView()
                        } label: {
                            Label("数据源", systemImage: "square.and.arrow.down")
                        }
                        
                        /* NavigationLink {
                         CustomizeView()
                         } label: {
                         Label("个性化", systemImage: "paintpalette")
                         } */
                    }
                }
                
                Section(header: Text("实用工具")) {
                    if let account = (accounts.first {
                        $0.provider == .jaccount
                    }), account.enabledFeatures.contains(.canvas), account.bizData["canvas_token"] != nil {
                        NavigationLink {
                            CanvasEventsView()
                        } label: {
                            Label("作业", systemImage: "book.pages")
                        }
                    }
                    
                    NavigationLink {
                        NotificationView()
                    } label: {
                        Label("教务通知", systemImage: "megaphone")
                    }
                    
                    if let account = (accounts.first {
                        $0.provider == .jaccount
                    }), account.enabledFeatures.contains(.campus_card) {
                        NavigationLink {
                            CampusCardListView()
                        } label: {
                            Label("校园卡", systemImage: "person.text.rectangle")
                        }
                    }
                    
                    NavigationLink {
                        BusMapView()
                    } label: {
                        Label("校园巴士", systemImage: "bus")
                    }
                }
                
                NavigationLink {
                    AboutView()
                } label: {
                    Label("关于", systemImage: "info.circle")
                }
            }
            .navigationBarTitle("我的")
            .toolbar(hideTabBar ? .hidden : .automatic, for: .tabBar)
        }
    }
}
