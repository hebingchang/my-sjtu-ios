//
//  AccountView.swift
//  MySJTU
//
//  Created by boar on 2024/09/28.
//

import SwiftUI

struct CanvasLinkView: View {
    var provider: Provider

    @AppStorage("accounts") private var accounts: [WebAuthAccount] = []
    @Environment(\.dismiss) private var dismiss

    @State private var status: CanvasLinkStatus = .initializing
    @State private var loading = true
    @State private var primaryButtonLoading = false
    @State private var secondaryButtonLoading = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var isShowingManualTokenInput = false

    private enum CanvasLinkStatus {
        case initializing
        case iCloudHasToken
        case beforeCreateToken
        case tokenExists
        case createFinished
        case importFinished
        case internalError
    }

    private var isActionDisabled: Bool {
        primaryButtonLoading || secondaryButtonLoading
    }

    private var titleText: String {
        status == .internalError ? "创建令牌失败" : "创建 Canvas 令牌"
    }

    var body: some View {
        VStack {
            VStack(spacing: 40) {
                Image(uiImage: UIImage(named: "canvas_lms")!)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200)

                Text(titleText)
                    .font(.title)
                    .fontWeight(.medium)

                statusDescription
            }
            .padding([.top, .bottom])

            Spacer()

            actionButtons
                .padding()
        }
        .animation(.easeInOut, value: status)
        .animation(.easeInOut, value: loading)
        .frame(maxWidth: .infinity)
        .padding()
        .task {
            await loadInitialStatus()
        }
        .sheet(isPresented: $isShowingManualTokenInput) {
            NavigationStack {
                CanvasManualTokenInputView { token in
                    try await importTokenManually(token)
                }
            }
        }
        .alert("错误", isPresented: $showErrorAlert) {
        } message: {
            Text(errorMessage)
        }
    }

    @ViewBuilder
    private var statusDescription: some View {
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
                    EmptyView()
                }
            }
            .multilineTextAlignment(.center)
            .font(.body)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 16) {
            switch status {
            case .iCloudHasToken:
                loadingPrimaryButton(title: "导入 iCloud 中的令牌", isLoading: primaryButtonLoading) {
                    primaryButtonLoading = true
                    Task {
                        defer { primaryButtonLoading = false }
                        await importTokenFromiCloud()
                    }
                }

                Button("创建新令牌") {
                    secondaryButtonLoading = true
                    loading = true
                    Task {
                        defer {
                            secondaryButtonLoading = false
                            loading = false
                        }
                        do {
                            try await getExistingToken()
                        } catch {
                            handleInitialLoadError(error)
                        }
                    }
                }
                .disabled(isActionDisabled)

            case .tokenExists:
                loadingPrimaryButton(
                    title: "重新生成令牌",
                    isLoading: primaryButtonLoading
                ) {
                    primaryButtonLoading = true
                    Task {
                        defer { primaryButtonLoading = false }
                        await createCanvasToken()
                    }
                }

                Button("手动输入令牌") {
                    isShowingManualTokenInput = true
                }
                .disabled(isActionDisabled)
                .padding(.bottom, 16)

                Button("取消") {
                    dismiss()
                }
                .disabled(isActionDisabled)

            case .beforeCreateToken:
                loadingPrimaryButton(
                    title: "创建令牌",
                    isLoading: primaryButtonLoading
                ) {
                    primaryButtonLoading = true
                    Task {
                        defer { primaryButtonLoading = false }
                        await createCanvasToken()
                    }
                }

                Button("取消") {
                    dismiss()
                }
                .disabled(isActionDisabled)

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
                EmptyView()
            }
        }
    }

    private func loadingPrimaryButton(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
            .padding([.top, .bottom], 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isActionDisabled)
    }

    private func checkCanvasToken(token: String) async throws {
        let api = CanvasAPI(token: token)
        try await api.checkToken()
    }

    private func currentAccountIndex() -> Int? {
        accounts.firstIndex { $0.provider == provider }
    }

    private func canvasTokenStoreKey(for account: WebAuthAccount) -> String {
        "\(account.user.account)_canvas_token"
    }

    @MainActor
    private func storeCanvasToken(_ token: String, for account: WebAuthAccount, at index: Int) {
        accounts[index].bizData["canvas_token"] = token
        if !accounts[index].enabledFeatures.contains(.canvas) {
            accounts[index].enabledFeatures.append(.canvas)
        }
        NSUbiquitousKeyValueStore.default.set(token, forKey: canvasTokenStoreKey(for: account))
    }

    private func iCloudToken(for account: WebAuthAccount) -> String? {
        NSUbiquitousKeyValueStore.default.string(forKey: canvasTokenStoreKey(for: account))
    }

    @MainActor
    private func importTokenFromiCloud() async {
        guard let index = currentAccountIndex() else { return }
        let account = accounts[index]

        guard let token = iCloudToken(for: account) else { return }

        do {
            try await checkCanvasToken(token: token)
            storeCanvasToken(token, for: account, at: index)
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

    private func createCanvasToken(account: WebAuthAccount) async throws -> String {
        let api = CanvasAPI(cookies: account.cookies.compactMap { $0.httpCookie })
        try await api.openIdConnect()
        let tokens = try await api.getTokens()
        if let token = tokens.first(where: { $0.purpose == "MySJTU" }) {
            let newToken = try await api.regenerateToken(tokenId: token.id)
            return newToken.token
        }

        let newToken = try await api.generateToken()
        return newToken.token
    }

    @MainActor
    private func importTokenManually(_ token: String) async throws {
        guard let index = currentAccountIndex() else {
            throw APIError.noAccount
        }

        let account = accounts[index]
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        try await checkCanvasToken(token: trimmedToken)
        storeCanvasToken(trimmedToken, for: account, at: index)
        status = .importFinished
    }

    private func getExistingToken() async throws {
        guard let index = currentAccountIndex() else { return }
        let account = accounts[index]

        let api = CanvasAPI(cookies: account.cookies.compactMap { $0.httpCookie })
        try await api.openIdConnect()
        let tokens = try await api.getTokens()
        status = tokens.first(where: { $0.purpose == "MySJTU" }) == nil ? .beforeCreateToken : .tokenExists
    }

    @MainActor
    private func createCanvasToken() async {
        guard let index = currentAccountIndex() else {
            errorMessage = "当前 jAccount 没有有效的 Canvas 账户"
            status = .internalError
            return
        }

        let account = accounts[index]
        do {
            let token = try await createCanvasToken(account: account)
            storeCanvasToken(token, for: account, at: index)
            status = .createFinished
        } catch APIError.noAccount {
            errorMessage = "当前 jAccount 没有有效的 Canvas 账户"
            status = .internalError
        } catch {
            errorMessage = "由于未知错误，无法登录到 Canvas"
            status = .internalError
        }
    }

    @MainActor
    private func loadInitialStatus() async {
        guard let index = currentAccountIndex() else { return }
        let account = accounts[index]

        if let token = iCloudToken(for: account) {
            do {
                try await checkCanvasToken(token: token)
                status = .iCloudHasToken
            } catch APIError.sessionExpired {
                do {
                    try await getExistingToken()
                } catch {
                    handleInitialLoadError(error)
                }
            } catch {
                errorMessage = "内部错误，请稍后重试"
                status = .internalError
            }
            loading = false
            return
        }

        do {
            try await getExistingToken()
        } catch {
            handleInitialLoadError(error)
        }
        loading = false
    }

    private func handleInitialLoadError(_ error: Error) {
        if let apiError = error as? APIError, apiError == .noAccount {
            errorMessage = "您的 jAccount 没有有效的 Canvas 账户"
        } else {
            errorMessage = "内部错误，请稍后重试"
        }
        status = .internalError
    }
}

private struct CanvasManualTokenInputView: View {
    let onSubmit: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTokenFieldFocused: Bool
    @State private var token = ""
    @State private var isSubmitting = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                TextField("Canvas 令牌", text: $token, axis: .vertical)
                    .lineLimit(4...8)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isTokenFieldFocused)
            } footer: {
                Text("如果您已在其他设备复制 Canvas 令牌，可将其粘贴到这里。")
            }

            Section {
                Button {
                    submitToken()
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("导入并启用 Canvas")
                        }
                        Spacer()
                    }
                }
                .disabled(isSubmitting || trimmedToken.isEmpty)
            }
        }
        .navigationTitle("手动输入令牌")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
                .disabled(isSubmitting)
            }
        }
        .task {
            isTokenFieldFocused = true
        }
        .alert("错误", isPresented: $showErrorAlert) {
        } message: {
            Text(errorMessage)
        }
    }

    private func submitToken() {
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await onSubmit(trimmedToken)
                dismiss()
            } catch APIError.sessionExpired {
                errorMessage = "手动输入的 Canvas 令牌无效或已过期，请检查后重试。"
                showErrorAlert = true
            } catch APIError.noAccount {
                errorMessage = "当前 jAccount 没有有效的 Canvas 账户"
                showErrorAlert = true
            } catch {
                errorMessage = "暂时无法验证该 Canvas 令牌，请稍后重试。"
                showErrorAlert = true
            }
        }
    }
}

struct AccountView: View {
    var provider: Provider

    @AppStorage("accounts") private var accounts: [WebAuthAccount] = []
    @State private var deleting = false
    @State private var sessionStatus: WebAuthStatus?
    @State private var featureLoading: [Feature: Bool] = [:]
    @State private var featureToggleOverride: [Feature: Bool] = [:]
    @State private var presentError = false
    @State private var featureError: String?
    @State private var showSignInSheet = false
    @State private var canvasStatus: CanvasStatus?
    @State private var showCanvasTokenAlert = false
    @State private var isShowingCanvasLink = false
    @State private var isShowingDeleteCanvasToken = false
    @State private var pendingCanvasEnablePreviousValue: Bool?
    @Environment(\.dismiss) private var dismiss

    private enum CanvasStatus {
        case ok
        case tokenExpired
        case internalError
        case hasNewICloudToken
    }

    private var currentAccount: WebAuthAccount? {
        accounts.first { $0.provider == provider }
    }

    private var canvasAlertMessage: String {
        switch canvasStatus {
        case .tokenExpired:
            return "Canvas 会话已过期，可能是令牌已被删除或重置。"
        case .hasNewICloudToken:
            return "Canvas 会话已过期，但是在 iCloud 云存储中有新的 Canvas 令牌可用。"
        default:
            return "无法连接到 Canvas，可能是网络问题或 Canvas 系统故障。"
        }
    }

    var body: some View {
        if currentAccount == nil && !deleting {
            SignInView(provider: provider) { account in
                withAnimation {
                    accounts.append(account)
                }
            }
        } else if let account = currentAccount {
            accountList(account)
        } else {
            ProgressView()
        }
    }

    private func accountList(_ account: WebAuthAccount) -> some View {
        List {
            accountHeader(account)
            accountInfoSection(account)
            featureSection(account)
            signOutButton(account)
        }
        .sheet(isPresented: $isShowingCanvasLink, onDismiss: {
            handleCanvasLinkDismiss(for: account.provider)
        }) {
            NavigationStack {
                CanvasLinkView(provider: provider)
                    .navigationTitle("连接 Canvas 账户")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert("错误", isPresented: $presentError, presenting: featureError) { _ in
        } message: { details in
            Text(details)
        }
        .sheet(isPresented: $showSignInSheet) {
            SignInView(provider: provider) { account in
                showSignInSheet = false
                Task {
                    sessionStatus = nil
                    if let index = accountIndex(for: account.provider) {
                        accounts[index] = account
                    }
                    sessionStatus = try? await account.checkSession()
                }
            }
        }
        .alert("取消 Canvas 绑定", isPresented: $isShowingDeleteCanvasToken) {
            Button("否", role: .cancel) {
                removeCanvasFeatureLocally(for: account.provider)
                featureLoading[.canvas] = false
                finalizeFeatureToggle(.canvas)
            }
            Button("是", role: .destructive) {
                revokeCanvasFeature(for: account)
            }
        } message: {
            Text("是否同时注销 Canvas 令牌？\n如果您有其他设备正在使用此 Canvas 账户，请选择“否”。")
        }
    }

    private func accountHeader(_ account: WebAuthAccount) -> some View {
        HStack {
            Spacer()
            VStack {
                avatarView(for: account)
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
    }

    @ViewBuilder
    private func avatarView(for account: WebAuthAccount) -> some View {
        if let urlString = account.user.avatar ?? account.user.photo {
            AsyncImage(url: URL(string: urlString), transaction: Transaction(animation: .easeInOut)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
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
    }

    private func accountInfoSection(_ account: WebAuthAccount) -> some View {
        Section(header: Text("账户信息")) {
            sessionRow
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
            await refreshSession(for: account)
        }
    }

    @ViewBuilder
    private var sessionRow: some View {
        if sessionStatus == .expired {
            Button {
                showSignInSheet = true
            } label: {
                HStack {
                    Text("SSO 会话")
                        .foregroundStyle(Color(UIColor.label))
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
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
    }

    private func featureSection(_ account: WebAuthAccount) -> some View {
        Section(header: Text("账户授权")) {
            ForEach(provider.get().features, id: \.feature) { requirement in
                HStack {
                    Text(requirement.feature.name)
                    Spacer()

                    if featureLoading[requirement.feature] == true {
                        ProgressView()
                    }

                    Toggle(
                        isOn: Binding(
                            get: {
                                isFeatureEnabled(requirement.feature)
                            },
                            set: { newValue in
                                let previousValue = isFeatureEnabled(requirement.feature)
                                featureToggleOverride[requirement.feature] = newValue
                                handleFeatureToggle(
                                    feature: requirement.feature,
                                    isEnabled: newValue,
                                    provider: account.provider,
                                    previousValue: previousValue
                                )
                            }
                        )
                    ) {}
                    .disabled(
                        requirement.required ||
                            sessionStatus == nil ||
                            featureLoading[requirement.feature] == true
                    )
                }
            }
        }
        .task {
            await validateCanvasTokenIfNeeded(for: account)
        }
        .alert("Canvas 错误", isPresented: $showCanvasTokenAlert) {
            canvasAlertActions(for: account)
        } message: {
            Text(canvasAlertMessage)
        }
    }

    @ViewBuilder
    private func canvasAlertActions(for account: WebAuthAccount) -> some View {
        if canvasStatus == .tokenExpired {
            Button("重新生成令牌") {
                regenerateCanvasToken(for: account)
            }
            Button("关闭 Canvas 功能") {
                removeCanvasFeatureLocally(for: account.provider)
                featureLoading[.canvas] = false
            }
            Button("以后", role: .cancel) {
            }
        } else if canvasStatus == .hasNewICloudToken {
            Button("从 iCloud 更新令牌") {
                guard
                    let index = accountIndex(for: account.provider),
                    let token = iCloudCanvasToken(for: account)
                else {
                    return
                }
                accounts[index].bizData["canvas_token"] = token
            }
            Button("以后", role: .cancel) {
            }
        }
    }

    private func signOutButton(_ account: WebAuthAccount) -> some View {
        Button {
            deleting = true
            HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
            accounts.removeAll(where: { $0.provider == account.provider })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } label: {
            Text("退出登录")
                .frame(maxWidth: .infinity)
                .padding([.top, .bottom], 4)
        }
    }

    private func accountIndex(for provider: Provider) -> Int? {
        accounts.firstIndex { $0.provider == provider }
    }

    private func canvasTokenStoreKey(for account: WebAuthAccount) -> String {
        "\(account.user.account)_canvas_token"
    }

    private func iCloudCanvasToken(for account: WebAuthAccount) -> String? {
        NSUbiquitousKeyValueStore.default.string(forKey: canvasTokenStoreKey(for: account))
    }

    private func appendFeature(_ feature: Feature, for provider: Provider) {
        guard let index = accountIndex(for: provider) else { return }
        if !accounts[index].enabledFeatures.contains(feature) {
            accounts[index].enabledFeatures.append(feature)
        }
    }

    private func removeCanvasFeatureLocally(for provider: Provider) {
        guard let index = accountIndex(for: provider) else { return }
        accounts[index].bizData.removeValue(forKey: "canvas_token")
        accounts[index].enabledFeatures.removeAll { $0 == .canvas }
    }

    private func isFeatureEnabled(_ feature: Feature) -> Bool {
        if let override = featureToggleOverride[feature] {
            return override
        }

        guard let freshAccount = currentAccount else { return false }
        return freshAccount.enabledFeatures.contains(feature)
    }

    private func finalizeFeatureToggle(_ feature: Feature) {
        featureToggleOverride.removeValue(forKey: feature)
    }

    private func rollbackFeatureToggle(_ feature: Feature, to _: Bool) {
        featureToggleOverride.removeValue(forKey: feature)
    }

    private func handleFeatureToggle(
        feature: Feature,
        isEnabled: Bool,
        provider: Provider,
        previousValue: Bool
    ) {
        if isEnabled {
            enableFeature(feature, provider: provider, previousValue: previousValue)
        } else {
            disableFeature(feature, provider: provider, previousValue: previousValue)
        }
    }

    private func enableFeature(_ feature: Feature, provider: Provider, previousValue: Bool) {
        guard let index = accountIndex(for: provider) else {
            rollbackFeatureToggle(feature, to: previousValue)
            return
        }

        switch feature {
        case .canvas:
            featureLoading[.canvas] = true
            pendingCanvasEnablePreviousValue = previousValue
            isShowingCanvasLink = true

        case .examAndGrade:
            featureLoading[.examAndGrade] = true
            Task {
                defer { featureLoading[.examAndGrade] = false }
                do {
                    let api = ElectSysAPI(cookies: accounts[index].cookies.compactMap { $0.httpCookie })
                    try await api.openIdConnect()
                    appendFeature(.examAndGrade, for: provider)
                    finalizeFeatureToggle(.examAndGrade)
                } catch {
                    featureError = "无法登录教学信息服务网"
                    presentError = true
                    rollbackFeatureToggle(.examAndGrade, to: previousValue)
                }
            }

        case .unicode:
            featureLoading[.unicode] = true
            Task {
                defer { featureLoading[.unicode] = false }
                do {
                    let api = SJTUOpenAPI(tokens: accounts[index].tokens)
                    let unicode = try await api.getUnicode()
                    if unicode.status == -1 {
                        featureError = "当前 jAccount 没有开通思源码"
                        presentError = true
                        rollbackFeatureToggle(.unicode, to: previousValue)
                    } else {
                        appendFeature(.unicode, for: provider)
                        finalizeFeatureToggle(.unicode)
                    }
                } catch {
                    featureError = "获取思源码状态时发生错误"
                    presentError = true
                    rollbackFeatureToggle(.unicode, to: previousValue)
                }
            }

        case .campusCard:
            featureLoading[.campusCard] = true
            Task {
                defer { featureLoading[.campusCard] = false }
                do {
                    let api = SJTUOpenAPI(tokens: accounts[index].tokens)
                    let cards = try await api.getCampusCards()
                    if cards.isEmpty {
                        featureError = "当前 jAccount 没有关联的校园卡"
                        presentError = true
                        rollbackFeatureToggle(.campusCard, to: previousValue)
                    } else {
                        appendFeature(.campusCard, for: provider)
                        finalizeFeatureToggle(.campusCard)
                    }
                } catch {
                    featureError = "获取校园卡信息时发生错误"
                    presentError = true
                    rollbackFeatureToggle(.campusCard, to: previousValue)
                }
            }

        default:
            appendFeature(feature, for: provider)
            finalizeFeatureToggle(feature)
        }
    }

    private func disableFeature(_ feature: Feature, provider: Provider, previousValue: Bool) {
        guard let index = accountIndex(for: provider) else {
            rollbackFeatureToggle(feature, to: previousValue)
            return
        }

        switch feature {
        case .canvas:
            featureLoading[.canvas] = true
            isShowingDeleteCanvasToken = true
        default:
            accounts[index].enabledFeatures.removeAll { $0 == feature }
            finalizeFeatureToggle(feature)
        }
    }

    private func handleCanvasLinkDismiss(for provider: Provider) {
        defer {
            featureLoading[.canvas] = false
            pendingCanvasEnablePreviousValue = nil
        }

        guard let previousValue = pendingCanvasEnablePreviousValue else {
            finalizeFeatureToggle(.canvas)
            return
        }

        let isCanvasEnabled = accounts.first(where: { $0.provider == provider })?.enabledFeatures.contains(.canvas) == true
        if isCanvasEnabled {
            finalizeFeatureToggle(.canvas)
        } else {
            rollbackFeatureToggle(.canvas, to: previousValue)
        }
    }

    private func refreshSession(for account: WebAuthAccount) async {
        do {
            if let index = accountIndex(for: account.provider) {
                accounts[index] = try await account.refreshSession()
            }
        } catch {
            print(error)
        }

        sessionStatus = try? await account.checkSession()
    }

    private func checkCanvasToken(token: String) async throws {
        let api = CanvasAPI(token: token)
        try await api.checkToken()
    }

    private func createCanvasToken(account: WebAuthAccount) async throws -> String {
        let api = CanvasAPI(cookies: account.cookies.compactMap { $0.httpCookie })
        try await api.openIdConnect()
        let tokens = try await api.getTokens()
        if let token = tokens.first(where: { $0.purpose == "MySJTU" }) {
            let newToken = try await api.regenerateToken(tokenId: token.id)
            return newToken.token
        }

        let newToken = try await api.generateToken()
        return newToken.token
    }

    private func deleteCanvasToken(account: WebAuthAccount) async throws {
        let api = CanvasAPI(cookies: account.cookies.compactMap { $0.httpCookie })
        try await api.openIdConnect()
        let tokens = try await api.getTokens()
        if let token = tokens.first(where: { $0.purpose == "MySJTU" }) {
            _ = try await api.deleteToken(tokenId: token.id)
        }
    }

    private func validateCanvasTokenIfNeeded(for account: WebAuthAccount) async {
        guard
            account.enabledFeatures.contains(.canvas),
            let token = account.bizData["canvas_token"]
        else {
            return
        }

        featureLoading[.canvas] = true
        do {
            try await checkCanvasToken(token: token)
            canvasStatus = .ok
            featureLoading[.canvas] = false
        } catch APIError.sessionExpired {
            await resolveExpiredCanvasToken(for: account)
        } catch {
            canvasStatus = .internalError
            featureLoading[.canvas] = false
            showCanvasTokenAlert = true
        }
    }

    private func resolveExpiredCanvasToken(for account: WebAuthAccount) async {
        if let iCloudToken = iCloudCanvasToken(for: account) {
            do {
                try await checkCanvasToken(token: iCloudToken)
                canvasStatus = .hasNewICloudToken
            } catch {
                canvasStatus = .tokenExpired
            }
        } else {
            canvasStatus = .tokenExpired
        }

        featureLoading[.canvas] = false
        showCanvasTokenAlert = true
    }

    private func regenerateCanvasToken(for account: WebAuthAccount) {
        guard let index = accountIndex(for: account.provider) else { return }
        featureLoading[.canvas] = true

        Task {
            defer { featureLoading[.canvas] = false }
            do {
                let token = try await createCanvasToken(account: account)
                accounts[index].bizData["canvas_token"] = token
                NSUbiquitousKeyValueStore.default.set(token, forKey: canvasTokenStoreKey(for: account))
            } catch APIError.noAccount {
                featureError = "当前 jAccount 没有有效的 Canvas 账户"
                presentError = true
                removeCanvasFeatureLocally(for: account.provider)
            } catch {
                print(error)
                featureError = "由于未知错误，无法登录到 Canvas"
                presentError = true
                removeCanvasFeatureLocally(for: account.provider)
            }
        }
    }

    private func revokeCanvasFeature(for account: WebAuthAccount) {
        guard let index = accountIndex(for: account.provider) else { return }

        Task {
            do {
                if canvasStatus == .ok {
                    try await deleteCanvasToken(account: account)
                }
                NSUbiquitousKeyValueStore.default.removeObject(forKey: canvasTokenStoreKey(for: account))
                accounts[index].bizData.removeValue(forKey: "canvas_token")
                accounts[index].enabledFeatures.removeAll { $0 == .canvas }
            } catch {
                print(error)
            }

            featureLoading[.canvas] = false
            finalizeFeatureToggle(.canvas)
        }
    }
}

#Preview {
    AccountView(provider: .jaccount)
}
