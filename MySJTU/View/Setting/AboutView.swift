//
//  AboutView.swift
//  MySJTU
//
//  Created by boar on 2024/11/10.
//

import SwiftUI
import AcknowList

struct AboutView: View {
    var body: some View {
        List {
            Section(header: Text("应用信息")) {
                HStack {
                    Label("版本", systemImage: "info.circle")
                    Spacer()
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")+\(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "")")
                        .font(.callout)
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                }
            }
            
            NavigationLink {
                AcknowledgeView()
            } label: {
                Label("开源软件许可", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        }
        .navigationBarTitle("关于")
    }
}

#Preview {
    AboutView()
}
