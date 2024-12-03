//
//  ProfileView.swift
//  MySJTU
//
//  Created by boar on 2024/09/28.
//

import SwiftUI
import WidgetKit

struct CollegeItem: Identifiable {
    let id: College
    let name: String
}

struct ProfileView: View {
    @AppStorage("collegeId", store: UserDefaults.shared) var collegeId: College = .sjtu
    @EnvironmentObject private var appConfig: AppConfig
    
    private let colleges = [
        CollegeItem(id: College.sjtu, name: "本部（本科）"),
        CollegeItem(id: College.sjtug, name: "本部（研究生）"),
        CollegeItem(id: College.shsmu, name: "医学院"),
    ]
    
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
                        
                        Picker(selection: $collegeId) {
                            ForEach(colleges, id: \.id) { college in
                                Text(college.name).tag(college.id)
                            }
                        } label: {
                            Label("数据源", systemImage: "square.and.arrow.down")
                        }
                        .pickerStyle(.navigationLink)
                        
                        /* NavigationLink {
                         CustomizeView()
                         } label: {
                         Label("个性化", systemImage: "paintpalette")
                         } */
                    }
                }
                
                NavigationLink {
                    AboutView()
                } label: {
                    Label("关于", systemImage: "info.circle")
                }
            }
            .navigationBarTitle("我的")
            .onChange(of: collegeId) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
