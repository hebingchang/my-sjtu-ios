//
//  CustomizeView.swift
//  MySJTU
//
//  Created by boar on 2024/11/26.
//

import SwiftUI

struct CustomizeView: View {
    var body: some View {
        List {
            Section(header: Text("背景")) {
                NavigationLink {
                    ScheduleHeaderBackground()
                } label: {
                    Label("日程页导航栏背景", systemImage: "list.dash.header.rectangle")
                }
            }
        }
        .navigationBarTitle("个性化")
    }
}

#Preview {
    CustomizeView()
}
