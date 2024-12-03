//
//  AccountView.swift
//  MySJTU
//
//  Created by boar on 2024/09/28.
//

import SwiftUI

struct CanvasLinkView: View {
    var provider: Provider
    
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @Environment(\.dismiss) var dismiss

    @State private var status: CanvasLinkStatus = .iCloudLoading
    @State private var loading: Bool = true
    @State private var buttonLoading: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    private enum CanvasLinkStatus {
        case iCloudLoading, iCloudHasToken, iCloudImporting
        case tokenLoading, beforeCreateToken, tokenExists, tokenCreating
        case createFinished, importFinished
        case internalError
    }
    
    private func checkCanvasToken(token: String) async throws {
        let api = CanvasAPI(token: token)
        try await api.checkToken()
    }
    
    private func importTokenFromiCloud() async throws {
        guard let index = (accounts.firstIndex {
            $0.provider == provider
        }) else {
            return
        }
        let account = accounts[index]

        if let iCloudToken = NSUbiquitousKeyValueStore().string(forKey: "\(account.user.account)_canvas_token") {
            do {
                try await checkCanvasToken(token: iCloudToken)
                accounts[index].bizData["canvas_token"] = iCloudToken
                accounts[index].enabledFeatures.append(.canvas)
                status = .importFinished
            } catch APIError.sessionExpired {
                errorMessage = "iCloud 中的 Canvas 令牌已过期，请重新生成令牌"
                showErrorAlert = true
                status = .iCloudHasToken
            } catch {
                errorMessage = "内部错误，请稍后重试"
                showErrorAlert = true
                status = .iCloudHasToken
            }
        }
    }
    
    private func createCanvasToken(account: WebAuthAccount) async throws -> String {
        let api = CanvasAPI(cookies: account.cookies.map { $0.httpCookie! })
        try await api.openIdConnect()
        let tokens = try await api.getTokens()
        if let token = tokens.first(where: { $0.purpose == "MySJTU" }) {
            // regenerate token
            let newToken = try await api.regenerateToken(tokenId: token.id)
            return newToken.token
        } else {
            // generate new token
            let newToken = try await api.generateToken()
            return newToken.token
        }
    }

    private func getExistingToken() async throws {
        guard let account = (accounts.first {
            $0.provider == provider
        }) else {
            return
        }

        let api = CanvasAPI(cookies: account.cookies.map { $0.httpCookie! })
        try await api.openIdConnect()
        let tokens = try await api.getTokens()
        if tokens.first(where: { $0.purpose == "MySJTU" }) != nil {
            status = .tokenExists
        } else {
            status = .beforeCreateToken
        }
    }
    
    private func createCanvasToken() async throws {
        guard let index = (accounts.firstIndex {
            $0.provider == provider
        }) else {
            throw APIError.noAccount
        }
        let account = accounts[index]

        do {
            let token = try await createCanvasToken(account: account)
            accounts[index].bizData["canvas_token"] = token
            accounts[index].enabledFeatures.append(.canvas)
            NSUbiquitousKeyValueStore.default.set(token, forKey: "\(account.user.account)_canvas_token")
            status = .createFinished
        } catch APIError.noAccount {
            errorMessage = "当前 jAccount 没有有效的 Canvas 账户"
            status = .internalError
        } catch {
            errorMessage = "由于未知错误，无法登录到 Canvas"
            status = .internalError
        }
    }

    var body: some View {
        VStack {
            VStack(spacing: 40) {
                Image(uiImage: UIImage(named: "canvas_lms")!)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200)
                
                if status == .internalError {
                    Text("创建令牌失败")
                        .font(.title)
                        .fontWeight(.medium)
                } else {
                    Text("创建 Canvas 令牌")
                        .font(.title)
                        .fontWeight(.medium)
                }
                
                if loading {
                    ProgressView()
                } else {
                    VStack(spacing: 8) {
                        switch status {
                        case .iCloudHasToken:
                            Text("在 iCloud 云存储中已有当前 jAccount 的 Canvas 令牌。")
                            Text("是否使用该令牌？")
                        case .createFinished:
                            Text("令牌创建成功。")
                        case .importFinished:
                            Text("令牌导入成功。")
                        case .tokenExists:
                            Text("您的 Canvas 账户中已有名为 MySJTU 的令牌。")
                            Text("是否重置该令牌？")
                        case .beforeCreateToken:
                            Text("「交课表」将在您的 Canvas 账户中创建一个名为 MySJTU 的令牌。请不要删除或重置该令牌。")
                            Text("是否继续？")
                        case .internalError:
                            Text(errorMessage)
                        default:
                            Text("")
                        }
                    }
                    .multilineTextAlignment(.center)
                    .font(.body)
                }
            }
            .padding([.top, .bottom])
            
            Spacer()
            
            VStack(spacing: 16) {
                switch status {
                case .iCloudHasToken, .iCloudImporting:
                    Button {
                        buttonLoading = true
                        status = .iCloudImporting
                        Task {
                            try await importTokenFromiCloud()
                            buttonLoading = false
                        }
                    } label: {
                        if buttonLoading && status == .iCloudImporting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding([.top, .bottom], 6)
                        } else {
                            Text("导入 iCloud 中的令牌")
                                .frame(maxWidth: .infinity)
                                .padding([.top, .bottom], 6)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(buttonLoading)
                    
                    Button {
                        buttonLoading = true
                        loading = true
                        status = .tokenLoading
                        Task {
                            try await getExistingToken()
                            buttonLoading = false
                            loading = false
                        }
                    } label: {
                        Text("创建新令牌")
                    }
                    .disabled(buttonLoading)
                case .tokenExists, .beforeCreateToken, .tokenCreating:
                    Button {
                        buttonLoading = true
                        status = .tokenCreating
                        Task {
                            try await createCanvasToken()
                            buttonLoading = false
                        }
                    } label: {
                        if buttonLoading && status == .tokenCreating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding([.top, .bottom], 6)
                        } else {
                            Text(status == .tokenExists ? "重新生成令牌" : "创建令牌")
                                .frame(maxWidth: .infinity)
                                .padding([.top, .bottom], 6)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(buttonLoading)
                    
                    Button {
                        dismiss()
                    } label: {
                        Text("取消")
                    }
                    .disabled(buttonLoading)
                case .importFinished, .createFinished, .internalError:
                    Button {
                        dismiss()
                    } label: {
                        Text("完成")
                            .frame(maxWidth: .infinity)
                            .padding([.top, .bottom], 6)
                    }
                    .buttonStyle(.borderedProminent)
                default:
                    Text("")
                }
            }
        }
        .animation(.easeInOut, value: status)
        .animation(.easeInOut, value: loading)
        .padding()
        .task {
            guard let account = (accounts.first {
                $0.provider == provider
            }) else {
                return
            }
            
            // check token from iCloud
            if let iCloudToken = NSUbiquitousKeyValueStore().string(forKey: "\(account.user.account)_canvas_token") {
                do {
                    try await checkCanvasToken(token: iCloudToken)
                    status = .iCloudHasToken
                } catch APIError.sessionExpired {
                    status = .tokenLoading
                } catch {
                    errorMessage = "内部错误，请稍后重试"
                    status = .internalError
                }
            } else {
                status = .tokenLoading
            }
            loading = false
        }
        .alert("错误", isPresented: $showErrorAlert) {
        } message: {
            Text(errorMessage)
        }
    }
}

struct AccountView: View {
    var provider: Provider
    @AppStorage("accounts") var accounts: [WebAuthAccount] = []
    @State private var toggle = false
    @State private var deleting = false
    @State private var sessionStatus: WebAuthStatus?
    @State private var featureLoading: [Feature: Bool] = [:]
    @State private var presentError: Bool = false
    @State private var featureError: String?
    @State private var canvasEnableStatus: CanvasEnableStatus?
    @State private var showSignInSheet: Bool = false
    @State private var canvasStatus: CanvasStatus?
    @State private var showCanvasTokenAlert: Bool = false
    @State private var isShowingCanvasLink: Bool = false
    @State private var isShowingDeleteCanvasToken: Bool = false
    @Environment(\.dismiss) var dismiss
    
    private enum CanvasStatus {
        case ok
        case tokenExpired
        case internalError
        case hasNewICloudToken
    }
    
    private enum CanvasEnableStatus {
        case iCloud
        case existingToken
        case newToken
    }
    
    private func checkCanvasToken(token: String) async throws {
        let api = CanvasAPI(token: token)
        try await api.checkToken()
    }

    private func createCanvasToken(account: WebAuthAccount) async throws -> String {
        let api = CanvasAPI(cookies: account.cookies.map { $0.httpCookie! })
        try await api.openIdConnect()
        let tokens = try await api.getTokens()
        if let token = tokens.first(where: { $0.purpose == "MySJTU" }) {
            // regenerate token
            let newToken = try await api.regenerateToken(tokenId: token.id)
            return newToken.token
        } else {
            // generate new token
            let newToken = try await api.generateToken()
            return newToken.token
        }
    }

    private func deleteCanvasToken(account: WebAuthAccount) async throws {
        let api = CanvasAPI(cookies: account.cookies.map { $0.httpCookie! })
        try await api.openIdConnect()
        let tokens = try await api.getTokens()
        if let token = tokens.first(where: { $0.purpose == "MySJTU" }) {
            // delete token
            _ = try await api.deleteToken(tokenId: token.id)
        }
    }

    var body: some View {
        let account = accounts.first {
            $0.provider == provider
        }

        if account == nil && !deleting {
            SignInView(provider: provider) { account in
                withAnimation {
                    self.accounts.append(account)
                }
            }
        } else if let account {
            List {
                HStack {
                    Spacer()
                    VStack {
                        if let avatar = account.user.avatar {
                            AsyncImage(url: URL(string: avatar), transaction: Transaction(animation: .easeInOut)) { phase in
                                if let image = phase.image {
                                    image.resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if phase.error != nil {
                                    Image(uiImage: UIImage(named: "avatar_placeholder")!)
                                        .resizable()
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(width: 96, height: 96)
                            .background(Color.white)
                            .clipShape(Circle())
                        } else if let photo = account.user.photo {
                            AsyncImage(url: URL(string: photo), transaction: Transaction(animation: .easeInOut)) { phase in
                                if let image = phase.image {
                                    image.resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if phase.error != nil {
                                    Image(uiImage: UIImage(named: "avatar_placeholder")!)
                                        .resizable()
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(width: 96, height: 96)
                            .background(Color.white)
                            .clipShape(Circle())
                        } else {
                            Image(uiImage: UIImage(named: "avatar_placeholder")!)
                                .resizable()
                                .frame(width: 96, height: 96)
                                .clipShape(Circle())
                        }

                        Text(account.user.name)
                            .font(.title)
                            .fontWeight(.bold)

                        Text(account.user.account)
                            .font(.title3)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                    Spacer()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section(header: Text("账户信息")) {
                    if sessionStatus == .expired {
                        Button {
                            showSignInSheet = true
                        } label: {
                            HStack {
                                Text("SSO 会话")
                                    .foregroundStyle(Color(UIColor.label))
                                Spacer()
                                HStack(spacing: 2) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                    Text("会话已过期")
                                        .font(.callout)
                                        .foregroundColor(.orange)
                                }
                                Image(systemName: "chevron.right")
                            }
                        }
                    } else {
                        HStack {
                            Text("SSO 会话")
                                .foregroundStyle(Color(UIColor.label))
                            Spacer()
                            switch sessionStatus {
                            case nil:
                                ProgressView()
                            case .error:
                                Text("错误")
                                    .font(.callout)
                                    .foregroundStyle(Color(UIColor.secondaryLabel))
                            case .connected:
                                Text("正常")
                                    .font(.callout)
                                    .foregroundStyle(Color(UIColor.secondaryLabel))
                            default:
                                Color.clear
                            }
                        }
                    }

                    HStack {
                        Text("学/工号")
                            .foregroundStyle(Color(UIColor.label))
                        Spacer()
                        Text(account.user.code)
                            .font(.callout)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                }
                .task {
                    do {
                        let index = self.accounts.firstIndex { $0.provider == account.provider }
                        self.accounts[index!] = try await account.refreshSession()
                    } catch {
                        print(error)
                    }
                    sessionStatus = try? await account.checkSession()
                }

                Section(header: Text("账户授权")) {
                    ForEach(provider.get().features, id: \.feature) { feature in
                        HStack {
                            Text(feature.feature.name)
                            Spacer()
                            
                            if let loading = featureLoading[feature.feature], loading {
                                ProgressView()
                            } else {
                                Toggle(isOn: Binding(
                                    get: {
                                        account.enabledFeatures.contains(feature.feature)
                                    },
                                    set: { newValue in
                                        if let index = accounts.firstIndex(where: { $0.provider == account.provider }) {
                                            if newValue {
                                                switch feature.feature {
                                                case .canvas:
                                                    featureLoading[.canvas] = true
                                                    isShowingCanvasLink = true
                                                case .unicode:
                                                    featureLoading[.unicode] = true
                                                    Task {
                                                        do {
                                                            let api = SJTUOpenAPI(tokens: accounts[index].tokens)
                                                            let unicode = try await api.getUnicode()
                                                            if unicode.status == -1 {
                                                                featureError = "当前 jAccount 没有开通思源码"
                                                                presentError = true
                                                            } else {
                                                                accounts[index].enabledFeatures.append(feature.feature)
                                                            }
                                                        } catch {
                                                            featureError = "获取思源码状态时发生错误"
                                                            presentError = true
                                                        }
                                                        featureLoading[.unicode] = false
                                                    }
                                                default:
                                                    accounts[index].enabledFeatures.append(feature.feature)
                                                }
                                            } else {
                                                switch feature.feature {
                                                case .canvas:
                                                    featureLoading[.canvas] = true
                                                    isShowingDeleteCanvasToken = true
                                                default:
                                                    accounts[index].enabledFeatures.removeAll {
                                                        $0 == feature.feature
                                                    }
                                                }
                                            }
                                        }
                                    }
                                )) {}
                                .disabled(feature.required || sessionStatus == nil)
                            }
                        }
                    }
                }
                .task {
                    if account.enabledFeatures.contains(.canvas), let token = account.bizData["canvas_token"] {
                        do {
                            featureLoading[.canvas] = true
                            try await checkCanvasToken(token: token)
                            canvasStatus = .ok
                            featureLoading[.canvas] = false
                        } catch APIError.sessionExpired {
                            // check icloud
                            if let iCloudToken = NSUbiquitousKeyValueStore().string(forKey: "\(account.user.account)_canvas_token") {
                                do {
                                    try await checkCanvasToken(token: iCloudToken)
                                    canvasStatus = .hasNewICloudToken
                                    featureLoading[.canvas] = false
                                    showCanvasTokenAlert = true
                                } catch {
                                    canvasStatus = .tokenExpired
                                    featureLoading[.canvas] = false
                                    showCanvasTokenAlert = true
                                }
                            } else {
                                canvasStatus = .tokenExpired
                                featureLoading[.canvas] = false
                                showCanvasTokenAlert = true
                            }
                        } catch {
                            canvasStatus = .internalError
                            featureLoading[.canvas] = false
                            showCanvasTokenAlert = true
                        }
                    }
                }
                .alert("Canvas 错误", isPresented: $showCanvasTokenAlert) {
                    if canvasStatus == .tokenExpired {
                        Button("重新生成令牌") {
                            if let index = accounts.firstIndex(where: { $0.provider == account.provider }) {
                                featureLoading[.canvas] = true
                                Task {
                                    do {
                                        let token = try await createCanvasToken(account: account)
                                        accounts[index].bizData["canvas_token"] = token
                                        NSUbiquitousKeyValueStore.default.set(token, forKey: "\(account.user.account)_canvas_token")
                                    } catch APIError.noAccount {
                                        featureError = "当前 jAccount 没有有效的 Canvas 账户"
                                        presentError = true
                                        accounts[index].bizData.removeValue(forKey: "canvas_token")
                                        accounts[index].enabledFeatures.removeAll {
                                            $0 == .canvas
                                        }
                                    } catch {
                                        print(error)
                                        featureError = "由于未知错误，无法登录到 Canvas"
                                        presentError = true
                                        accounts[index].bizData.removeValue(forKey: "canvas_token")
                                        accounts[index].enabledFeatures.removeAll {
                                            $0 == .canvas
                                        }
                                    }
                                    featureLoading[.canvas] = false
                                }
                            }
                        }
                        Button("关闭 Canvas 功能") {
                            if let index = accounts.firstIndex(where: { $0.provider == account.provider }) {
                                accounts[index].bizData.removeValue(forKey: "canvas_token")
                                accounts[index].enabledFeatures.removeAll {
                                    $0 == .canvas
                                }
                                featureLoading[.canvas] = false
                            }
                        }
                        Button("以后", role: .cancel) {
                            
                        }
                    } else if canvasStatus == .hasNewICloudToken {
                        Button("从 iCloud 更新令牌") {
                            if let index = accounts.firstIndex(where: { $0.provider == account.provider }), let iCloudToken = NSUbiquitousKeyValueStore().string(forKey: "\(account.user.account)_canvas_token") {
                                accounts[index].bizData["canvas_token"] = iCloudToken
                            }
                        }
                        Button("以后", role: .cancel) {
                            
                        }
                    }
                } message: {
                    switch canvasStatus {
                    case .tokenExpired:
                        Text("Canvas 会话已过期，可能是令牌已被删除或重置。")
                    case .hasNewICloudToken:
                        Text("Canvas 会话已过期，但是在 iCloud 云存储中有新的 Canvas 令牌可用。")
                    default:
                        Text("无法连接到 Canvas，可能是网络问题或 Canvas 系统故障。")
                    }
                }

                Button {
                    deleting = true
                    HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
                    self.accounts.removeAll(where: { $0.provider == account.provider })
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                } label: {
                    Text("退出登录")
                        .frame(maxWidth: .infinity)
                        .padding([.top, .bottom], 4)
                }
            }
            .sheet(isPresented: $isShowingCanvasLink, onDismiss: {
                featureLoading[.canvas] = false
            }) {
                NavigationStack {
                    CanvasLinkView(provider: provider)
                        .navigationTitle("连接 Canvas 账户")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .alert("错误", isPresented: $presentError, presenting: featureError) { details in
            } message: { details in
                Text(details)
            }
            .sheet(isPresented: $showSignInSheet) {
                SignInView(provider: provider) { account in
                    showSignInSheet = false
                    Task {
                        sessionStatus = nil
                        if let index = self.accounts.firstIndex(where: { $0.provider == account.provider }) {
                            self.accounts[index] = account
                        }
                        sessionStatus = try? await account.checkSession()
                    }
                }
            }
            .alert("取消 Canvas 绑定", isPresented: $isShowingDeleteCanvasToken) {
                Button("否", role: .cancel) {
                    if let index = accounts.firstIndex(where: { $0.provider == account.provider }) {
                        accounts[index].bizData.removeValue(forKey: "canvas_token")
                        accounts[index].enabledFeatures.removeAll {
                            $0 == .canvas
                        }
                        featureLoading[.canvas] = false
                    }
                }
                Button("是", role: .destructive) {
                    if let index = accounts.firstIndex(where: { $0.provider == account.provider }) {
                        Task {
                            do {
                                if canvasStatus == .ok {
                                    try await deleteCanvasToken(account: account)
                                }
                                NSUbiquitousKeyValueStore.default.removeObject(forKey: "\(account.user.account)_canvas_token")
                                accounts[index].bizData.removeValue(forKey: "canvas_token")
                                accounts[index].enabledFeatures.removeAll {
                                    $0 == .canvas
                                }
                            } catch {
                                print(error)
                            }
                            featureLoading[.canvas] = false
                        }
                    }
                }
            } message: {
                Text("是否同时注销 Canvas 令牌？\n如果您有其他设备正在使用此 Canvas 账户，请选择“否”。")
            }
        } else {
            ProgressView()
        }
    }
}

#Preview {
    AccountView(provider: .jaccount)
}
