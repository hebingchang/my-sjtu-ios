//
//  ProfileView.swift
//  MySJTU
//
//  Created by boar on 2024/09/28.
//

import SwiftUI

struct CollegeItem: Identifiable {
    let id: College
    let category: String
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
                        
                        NavigationLink {
                            CustomizeView()
                        } label: {
                            Label("个性化", systemImage: "paintpalette")
                        }
                    }
                }
                
                Section(header: Text("学在交大")) {
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

                    NavigationLink {
                        SelfStudyClassroomView()
                    } label: {
                        Label("自习教室", systemImage: "studentdesk")
                    }
                    
                    if let account = (accounts.first {
                        $0.provider == .jaccount
                    }), account.enabledFeatures.contains(.examAndGrade) {
                        NavigationLink {
                            ExamView()
                        } label: {
                            Label("考试与成绩", systemImage: "pencil.and.list.clipboard")
                        }
                    }
                }
                
                Section(header: Text("交大生活")) {
                    if let account = (accounts.first {
                        $0.provider == .jaccount
                    }), account.enabledFeatures.contains(.campusCard) {
                        NavigationLink {
                            CampusCardListView()
                        } label: {
                            Label("校园卡", systemImage: "person.text.rectangle")
                        }
                    }
                    
                    NavigationLink {
                        BusListView()
                    } label: {
                        Label("校园巴士", systemImage: "bus.fill")
                    }

//                    NavigationLink {
//                        PanoramaScreen()
//                    } label: {
//                        Label("VR", systemImage: "bus.fill")
//                    }
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
