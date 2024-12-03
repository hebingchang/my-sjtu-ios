//
//  AccountListView.swift
//  MySJTU
//
//  Created by boar on 2024/11/10.
//

import SwiftUI

struct AccountListView: View {
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []

    var body: some View {
        List {
            Section(header: Text("第三方登录")) {
                ForEach([Provider.jaccount, Provider.shsmu], id: \.self) { provider in
                    let account = accounts.first {
                        $0.provider == provider
                    }

                    NavigationLink {
                        AccountView(provider: provider)
                    } label: {
                        HStack {
                            Text(provider.get().name)
                                .foregroundStyle(Color(UIColor.label))
                            Spacer()
                            Text(account == nil ? "未登录" : account!.user.name)
                                .font(.callout)
                                .foregroundStyle(Color(UIColor.secondaryLabel))
                        }
                    }
                }
            }
        }
        .navigationBarTitle("账户")
    }
}

#Preview {
    AccountListView()
}
