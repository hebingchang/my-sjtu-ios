//
//  AboutView.swift
//  MySJTU
//
//  Created by boar on 2024/11/10.
//

import SwiftUI
import AcknowList

struct AboutView: View {
    private let shuiyuanDiscussionURL = URL(string: "https://shuiyuan.sjtu.edu.cn/t/topic/328264")!
    private let discussionQQGroupURL = URL(string: "https://qun.qq.com/universal-share/share?ac=1&authKey=iDf20PJOunNvVPGaO6NQ%2BFevvbU85qw2zejAIz15NQKmU%2BC80y3QpO7VQpCcEJVq&busi_data=eyJncm91cENvZGUiOiIxODYyODc2NTEiLCJ0b2tlbiI6Imh4Y0tXOVM3akdnMjBHcm9id3liM0Q1TWFid0NYWXI0WkhISjlEa0wrSiswOUJFYWRSZjFrVnZmdC92VE55OGUiLCJ1aW4iOiI5MzQ2MzI0MzcifQ%3D%3D&data=mn6ahZlKvwnRqtY0ZJpNeLTwNOVVIFjeS6aaxXXFe0qHMGjCTsdzXmteeZ22Ow2k_SJfzzYot4CQMwD4llIKTg&svctype=4&tempid=h5_group_info")!

    private var versionDescription: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

        if shortVersion.isEmpty { return buildVersion }
        if buildVersion.isEmpty { return shortVersion }
        return "\(shortVersion)+\(buildVersion)"
    }
    
    var body: some View {
        List {
            Section(header: Text("应用信息")) {
                HStack {
                    Label("版本", systemImage: "info.circle")
                    Spacer()
                    Text(versionDescription)
                        .font(.callout)
                        .foregroundStyle(Color(UIColor.secondaryLabel))
                }
            }
            
            Section(header: Text("反馈")) {
                NavigationLink {
                    FeedbackView()
                } label: {
                    Label("应用内反馈", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                }

                Link(destination: shuiyuanDiscussionURL) {
                    HStack(spacing: 12) {                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("水源社区讨论帖")
                                .foregroundStyle(Color(UIColor.label))
                            
                            Text("需要登录水源社区后访问")
                                .font(.footnote)
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.footnote)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                    
                }
                
                Link(destination: discussionQQGroupURL) {
                    HStack(spacing: 12) {
                        Text("反馈 QQ 群")
                            .foregroundStyle(Color(UIColor.label))
                        Spacer()
                        
                        Image(systemName: "arrow.up.right")
                            .font(.footnote)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
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
