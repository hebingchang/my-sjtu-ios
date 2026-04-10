import SwiftUI

private enum ModelSelection: Hashable {
    case fromList(String)
    case custom

    init(
        modelId: String?,
        availableModels: [AIService.AIModelInfo],
        defaultModelId: String? = nil
    ) {
        let trimmedModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedModelId,
           !trimmedModelId.isEmpty,
           availableModels.contains(where: { $0.id == trimmedModelId }) {
            self = .fromList(trimmedModelId)
        } else if let defaultModelId,
                  availableModels.contains(where: { $0.id == defaultModelId }) {
            self = .fromList(defaultModelId)
        } else {
            self = .custom
        }
    }

    static func defaultModelID(
        for provider: AIProvider,
        availableModels: [AIService.AIModelInfo]
    ) -> String? {
        switch provider {
        case .chatSJTU:
            return availableModels.first(where: { $0.id == "minimax" })?.id
        case .custom:
            return availableModels.first?.id
        }
    }

    init(
        modelId: String?,
        provider: AIProvider,
        availableModels: [AIService.AIModelInfo]
    ) {
        let trimmedModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultModelID = trimmedModelId?.isEmpty == false
            ? nil
            : Self.defaultModelID(for: provider, availableModels: availableModels)

        self.init(
            modelId: trimmedModelId,
            availableModels: availableModels,
            defaultModelId: defaultModelID
        )
    }

    var selectedModelId: String? {
        switch self {
        case .fromList(let id): return id
        case .custom: return nil
        }
    }
}

@MainActor
private struct AIToolPermissionsView: View {
    @Binding var store: AIToolPermissionStore

    var body: some View {
        Form {
            if store.isEmpty {
                Section {
                    Text("还没有工具被请求过。")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(store.providerEntries) { entry in
                        NavigationLink {
                            AIToolProviderPermissionsView(
                                store: $store,
                                baseURL: entry.baseURL
                            )
                        } label: {
                            HStack {
                                Text(AIToolPermissionStore.providerDisplayName(for: entry.baseURL))
                                Spacer()
                                Text("\(entry.tools.count) 个工具")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("按服务提供商分别管理工具权限。")
                }
            }
        }
        .navigationTitle("工具权限")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
private struct AIToolProviderPermissionsView: View {
    @Binding var store: AIToolPermissionStore

    let baseURL: String

    private var entry: AIToolPermissionStore.ProviderEntry? {
        store.providerEntries.first(where: { $0.baseURL == baseURL })
    }

    var body: some View {
        Form {
            if let entry {
                Section {
                    ForEach(entry.tools, id: \.name) { tool in
                        Picker(
                            AIToolPermissionStore.toolDisplayName(for: tool.name),
                            selection: policyBinding(for: tool.name)
                        ) {
                            ForEach(AIToolPermissionPolicy.allCases) { policy in
                                Text(policy.displayName)
                                    .tag(policy)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                } footer: {
                    Text("每个工具都可以设置为“始终允许”“下次询问”或“不允许”。")
                }
            } else {
                Section {
                    Text("这个 provider 目前没有工具权限记录。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(AIToolPermissionStore.providerDisplayName(for: baseURL))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policyBinding(for toolName: String) -> Binding<AIToolPermissionPolicy> {
        Binding(
            get: { store.policy(toolName: toolName, baseURL: baseURL) ?? .askNextTime },
            set: { store.setPolicy($0, toolName: toolName, baseURL: baseURL) }
        )
    }
}

@MainActor
private struct AICustomPromptEditor: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("可以在这里补充回答语气、角色设定、输出偏好等信息。")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
            }

            TextEditor(text: $text)
                .frame(minHeight: 132)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
        }
    }
}

@MainActor
private struct AICustomPromptSettingsView: View {
    @Binding var text: String
    @AppStorage("aiConfig") private var aiConfig = AIConfig()
    @State private var draft: String = ""
    @Environment(\.dismiss) private var dismiss

    private var hasChanges: Bool {
        draft != text
    }

    var body: some View {
        Form {
            Section {
                AICustomPromptEditor(text: $draft)
            } footer: {
                Text("留空则不附加。填写后会作为系统提示词的最后一段发送给模型，可用于补充回答语气、角色设定或输出偏好。")
            }
        }
        .navigationTitle("自定义提示词")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    text = draft
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    let previousConfig = aiConfig
                    var updatedConfig = previousConfig
                    updatedConfig.customSystemPrompt = trimmed.isEmpty ? nil : trimmed
                    if updatedConfig.rawValue != previousConfig.rawValue {
                        aiConfig = updatedConfig
                    }
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!hasChanges)
            }
        }
        .onAppear {
            draft = text
        }
    }
}

@MainActor
struct AISettingsView: View {
    private enum ChatSJTUTokenFetchTrigger {
        case restore
        case accountUpdate
        case userInitiated

        var shouldPresentErrors: Bool {
            self == .userInitiated
        }

        var shouldRevertSelectionOnFailure: Bool {
            self == .userInitiated
        }
    }

    @AppStorage("accounts") private var accounts: [WebAuthAccount] = []
    @AppStorage("aiConfig") private var aiConfig = AIConfig()
    @AppStorage("aiToolPermissions") private var toolPermissionStore = AIToolPermissionStore()

    @State private var isEnabled = false
    @State private var selectedProvider: AIProvider = .custom
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""

    @State private var isLoading = false
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var credentialValid = false
    @State private var availableModels: [AIService.AIModelInfo] = []
    @State private var modelSelection: ModelSelection = .custom
    @State private var customModelId: String = ""
    @State private var customSystemPrompt: String = ""

    @State private var errorMessage: String?
    @State private var showError = false
    @State private var didLoadStoredConfig = false
    @State private var currentChatSJTUTokenFetchID = UUID()

    @Environment(\.dismiss) private var dismiss

    private let chatSJTUTokenFetchRetryCount = 2
    private let chatSJTUTokenFetchRetryDelayNanoseconds: UInt64 = 700_000_000

    private var connectedJAccount: WebAuthAccount? {
        accounts.first { $0.provider == .jaccount && $0.status == .connected }
    }

    private var jAccount: WebAuthAccount? {
        connectedJAccount ?? accounts.first { $0.provider == .jaccount }
    }

    private var hasJAccount: Bool {
        connectedJAccount != nil
    }

    private var defaultProviderForEmptyConfiguration: AIProvider {
        hasJAccount ? .chatSJTU : .custom
    }

    private var restoredProvider: AIProvider {
        if let provider = aiConfig.provider {
            return provider
        }

        return aiConfig.hasStoredConfiguration ? .custom : defaultProviderForEmptyConfiguration
    }

    private var resolvedModelId: String {
        switch modelSelection {
        case .fromList(let id): return id
        case .custom: return customModelId
        }
    }

    private var resolvedModelDisplayName: String? {
        let trimmedModelId = resolvedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelId.isEmpty else {
            return nil
        }

        return availableModels
            .first(where: { $0.id == trimmedModelId })?
            .displayName
    }

    private var canSave: Bool {
        !resolvedModelId.isEmpty
    }

    private var customPromptSummary: String {
        customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未设置" : "已设置"
    }

    private var savedCapabilitiesForCurrentConfiguration: AIModelCapabilities {
        let resolvedSavedModel = aiConfig.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedCurrentModel = resolvedModelId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !resolvedCurrentModel.isEmpty,
              !resolvedSavedModel.isEmpty,
              selectedProvider == aiConfig.provider,
              resolvedSavedModel == resolvedCurrentModel
        else {
            return .init()
        }

        return aiConfig.capabilities
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                let oldValue = isEnabled
                isEnabled = newValue
                handleIsEnabledChange(from: oldValue, to: newValue)
            }
        )
    }

    private var selectedProviderBinding: Binding<AIProvider> {
        Binding(
            get: { selectedProvider },
            set: { newValue in
                let oldValue = selectedProvider
                selectedProvider = newValue
                handleSelectedProviderChange(from: oldValue, to: newValue)
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("启用 AI", isOn: isEnabledBinding)

                if isEnabled && !toolPermissionStore.isEmpty {
                    NavigationLink {
                        AIToolPermissionsView(store: $toolPermissionStore)
                    } label: {
                        HStack {
                            Text("工具权限")
                            Spacer()
                            Text("\(toolPermissionStore.providerEntries.count) 个提供商")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isEnabled {
                    NavigationLink {
                        AICustomPromptSettingsView(text: $customSystemPrompt)
                    } label: {
                        HStack {
                            Text("自定义提示词")
                            Spacer()
                            Text(customPromptSummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("状态与权限")
            }

            if isEnabled {
                providerSection
                apiConfigSection

                if credentialValid {
                    modelSection
                    capabilitySection
                    saveSection
                }
            }
        }
        .navigationTitle("AI 设置")
        .navigationBarTitleDisplayMode(.inline)
        .alert("错误", isPresented: $showError) {
            Button("确定") {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .onAppear {
            guard !didLoadStoredConfig else { return }
            loadFromConfig()
        }
        .onDisappear {
            currentChatSJTUTokenFetchID = UUID()
        }
        .onChange(of: accounts.rawValue) { _, _ in
            retryChatSJTUTokenFetchIfNeeded()
        }
    }

    @ViewBuilder
    private var providerSection: some View {
        Section("服务提供商") {
            Picker("提供商", selection: selectedProviderBinding) {
                ForEach(AIProvider.allCases) { provider in
                    if provider == .chatSJTU && !hasJAccount {
                        Text("\(provider.displayName)（需要 jAccount）")
                            .tag(provider)
                    } else {
                        Text(provider.displayName)
                            .tag(provider)
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(isLoading || isTesting)
    }

    @ViewBuilder
    private var apiConfigSection: some View {
        switch selectedProvider {
        case .custom:
            Section {
                HStack {
                    TextField("Base URL", text: $baseURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: baseURL) { _, _ in resetCredentialState() }
                    if credentialValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                HStack {
                    SecureField("API Key", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: apiKey) { _, _ in resetCredentialState() }
                    if credentialValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if !credentialValid {
                    Button {
                        testCredential()
                    } label: {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, 6)
                                Text("验证中...")
                            } else {
                                Text("验证凭据")
                            }
                            Spacer()
                        }
                    }
                    .disabled(baseURL.isEmpty || apiKey.isEmpty || isTesting || isSaving)
                }
            } header: {
                Text("API 配置")
            }
        case .chatSJTU:
            Section {
                LabeledContent("Base URL") {
                    Text(AIService.chatSJTUBaseURL)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("API Key") {
                    if isLoading {
                        ProgressView()
                    } else if credentialValid {
                        Text("已自动配置")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("待获取")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("API 配置")
            } footer: {
                if !hasJAccount {
                    Text("请先登录 jAccount 账号才能使用此服务。")
                        .foregroundStyle(.red)
                } else {
                    Text("将使用 jAccount 会话自动获取 token。")
                }
            }
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        Section {
            if !availableModels.isEmpty {
                Picker("从列表选择", selection: $modelSelection) {
                    ForEach(availableModels, id: \.id) { model in
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                            if model.name != nil {
                                Text(model.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(ModelSelection.fromList(model.id))
                    }
                    Divider()
                    Text("手动输入")
                        .tag(ModelSelection.custom)
                }
            }

            if modelSelection == .custom {
                TextField("模型 ID", text: $customModelId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Text("模型")
        } footer: {
            if modelSelection == .custom && !availableModels.isEmpty {
                Text("手动输入的模型 ID 需要确保有效。")
            }
        }
    }

    @ViewBuilder
    private var capabilitySection: some View {
        Section {
            capabilityRow(title: "Tool Calling", supported: savedCapabilitiesForCurrentConfiguration.supportsToolCalling)
            capabilityRow(title: "Responses API", supported: savedCapabilitiesForCurrentConfiguration.supportsResponsesAPI)
        } header: {
            Text("能力检测")
        } footer: {
            Text("保存配置时会检测并记录当前模型的能力。")
        }
    }

    @ViewBuilder
    private var saveSection: some View {
        Section {
            Button {
                save()
            } label: {
                HStack {
                    Spacer()
                    if isSaving {
                        ProgressView()
                            .padding(.trailing, 6)
                        Text("保存中...")
                    } else {
                        Text("保存")
                    }
                    Spacer()
                }
            }
            .disabled(!canSave || isLoading || isTesting || isSaving)
        }
    }

    @ViewBuilder
    private func capabilityRow(title: String, supported: Bool?) -> some View {
        LabeledContent(title) {
            Text(capabilityStatusText(for: supported))
                .foregroundStyle(capabilityStatusColor(for: supported))
        }
    }

    private func capabilityStatusText(for supported: Bool?) -> String {
        switch supported {
        case true: return "支持"
        case false: return "不支持"
        case nil: return "未检测"
        }
    }

    private func capabilityStatusColor(for supported: Bool?) -> Color {
        switch supported {
        case true: return .green
        case false: return .red
        case nil: return .secondary
        }
    }

    private func loadFromConfig() {
        didLoadStoredConfig = false
        isEnabled = aiConfig.isEnabled
        selectedProvider = restoredProvider
        baseURL = aiConfig.baseURL ?? ""
        apiKey = aiConfig.apiKey ?? ""
        customModelId = aiConfig.model ?? ""
        customSystemPrompt = aiConfig.customSystemPrompt ?? ""

        didLoadStoredConfig = true

        if isEnabled && selectedProvider == .chatSJTU {
            fetchChatSJTUToken(trigger: .restore)
        } else if aiConfig.hasValidConfiguration && selectedProvider == .custom {
            testCredential()
        }
    }

    private func handleSelectedProviderChange(from oldValue: AIProvider, to newValue: AIProvider) {
        guard didLoadStoredConfig, oldValue != newValue else {
            return
        }

        if newValue == .chatSJTU && isEnabled {
            fetchChatSJTUToken(
                revertTo: oldValue,
                revertEnabledTo: isEnabled,
                trigger: .userInitiated
            )
        } else if oldValue == .chatSJTU && newValue == .custom {
            currentChatSJTUTokenFetchID = UUID()
            isLoading = false
            resetCredentialState()
            baseURL = ""
            apiKey = ""
        }
    }

    private func handleIsEnabledChange(from oldValue: Bool, to newValue: Bool) {
        guard didLoadStoredConfig, oldValue != newValue else {
            return
        }

        guard aiConfig.isEnabled != newValue else {
            return
        }

        var updatedConfig = aiConfig
        updatedConfig.isEnabled = newValue
        commitAIConfig(updatedConfig)

        if newValue && selectedProvider == .chatSJTU {
            fetchChatSJTUToken(
                revertTo: .chatSJTU,
                revertEnabledTo: false,
                trigger: .userInitiated
            )
        } else if newValue,
                  selectedProvider == .custom,
                  !credentialValid,
                  !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            testCredential()
        } else if !newValue {
            currentChatSJTUTokenFetchID = UUID()
            isLoading = false
            toolPermissionStore.resetAuthorizedPermissions()
        }
    }

    private func commitAIConfig(_ updatedConfig: AIConfig) {
        guard updatedConfig.rawValue != aiConfig.rawValue else {
            return
        }

        aiConfig = updatedConfig
    }

    private func resetCredentialState() {
        credentialValid = false
        availableModels = []
        modelSelection = .custom
        customModelId = ""
    }

    private var savedModelForCurrentProvider: String? {
        guard selectedProvider == aiConfig.provider else { return nil }
        return aiConfig.model
    }

    private func testCredential() {
        isTesting = true
        Task {
            do {
                let models = try await AIService.fetchModels(baseURL: baseURL, apiKey: apiKey)
                await MainActor.run {
                    availableModels = models
                    credentialValid = true
                    let savedModel = savedModelForCurrentProvider
                    modelSelection = ModelSelection(
                        modelId: savedModel,
                        provider: selectedProvider,
                        availableModels: models
                    )
                    if case .custom = modelSelection {
                        customModelId = savedModel ?? ""
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    credentialValid = false
                    isTesting = false
                }
            }
        }
    }

    private func retryChatSJTUTokenFetchIfNeeded() {
        guard didLoadStoredConfig,
              isEnabled,
              selectedProvider == .chatSJTU,
              !credentialValid,
              !isLoading
        else {
            return
        }

        fetchChatSJTUToken(trigger: .accountUpdate)
    }

    private func fetchChatSJTUToken(
        revertTo fallback: AIProvider? = nil,
        revertEnabledTo fallbackEnabled: Bool? = nil,
        trigger: ChatSJTUTokenFetchTrigger
    ) {
        guard connectedJAccount != nil else {
            if trigger.shouldRevertSelectionOnFailure {
                selectedProvider = fallback != .chatSJTU ? (fallback ?? .custom) : .custom
                if let fallbackEnabled {
                    var updatedConfig = aiConfig
                    updatedConfig.isEnabled = fallbackEnabled
                    commitAIConfig(updatedConfig)
                    isEnabled = fallbackEnabled
                }
                errorMessage = AIServiceError.noJAccountSession.localizedDescription
                showError = true
            }
            return
        }

        let fetchID = UUID()
        currentChatSJTUTokenFetchID = fetchID
        isLoading = true
        resetCredentialState()
        let accountsSnapshot = accounts.rawValue

        Task {
            do {
                let (token, models) = try await loadChatSJTUTokenAndModels()
                await MainActor.run {
                    guard currentChatSJTUTokenFetchID == fetchID else {
                        return
                    }

                    guard selectedProvider == .chatSJTU, isEnabled else {
                        isLoading = false
                        return
                    }

                    baseURL = AIService.chatSJTUBaseURL
                    apiKey = token
                    availableModels = models
                    credentialValid = true
                    let savedModel = savedModelForCurrentProvider
                    modelSelection = ModelSelection(
                        modelId: savedModel,
                        provider: selectedProvider,
                        availableModels: models
                    )
                    if case .custom = modelSelection {
                        customModelId = savedModel ?? ""
                    }
                    isLoading = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard currentChatSJTUTokenFetchID == fetchID else {
                        return
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    guard currentChatSJTUTokenFetchID == fetchID else {
                        return
                    }

                    isLoading = false

                    guard selectedProvider == .chatSJTU else {
                        return
                    }

                    if !trigger.shouldPresentErrors, accounts.rawValue != accountsSnapshot {
                        fetchChatSJTUToken(trigger: .accountUpdate)
                        return
                    }

                    if trigger.shouldRevertSelectionOnFailure {
                        selectedProvider = fallback != .chatSJTU ? (fallback ?? .custom) : .custom
                        if let fallbackEnabled {
                            var updatedConfig = aiConfig
                            updatedConfig.isEnabled = fallbackEnabled
                            commitAIConfig(updatedConfig)
                            isEnabled = fallbackEnabled
                        } else {
                            isEnabled = aiConfig.isEnabled
                        }
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }

    private func loadChatSJTUTokenAndModels() async throws -> (String, [AIService.AIModelInfo]) {
        var lastError: Error = AIServiceError.tokenNotFound

        for attempt in 0...chatSJTUTokenFetchRetryCount {
            guard let account = connectedJAccount else {
                throw AIServiceError.noJAccountSession
            }

            do {
                let token = try await AIService.refreshChatSJTUToken(cookies: account.cookies)
                let models = try await AIService.fetchModels(
                    baseURL: AIService.chatSJTUBaseURL,
                    apiKey: token
                )
                return (token, models)
            } catch {
                if error is CancellationError {
                    throw error
                }

                lastError = error

                guard shouldRetryChatSJTUTokenFetch(after: error, attempt: attempt) else {
                    throw error
                }

                try await Task.sleep(nanoseconds: chatSJTUTokenFetchRetryDelayNanoseconds)
            }
        }

        throw lastError
    }

    private func shouldRetryChatSJTUTokenFetch(after error: Error, attempt: Int) -> Bool {
        guard attempt < chatSJTUTokenFetchRetryCount,
              let serviceError = error as? AIServiceError
        else {
            return false
        }

        switch serviceError {
        case .tokenNotFound, .loginFailed(_):
            return true
        default:
            return false
        }
    }

    private func save() {
        let provider = selectedProvider
        let resolvedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelId = resolvedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelDisplayName = resolvedModelDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCustomSystemPrompt = customSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !modelId.isEmpty else {
            return
        }

        isSaving = true

        Task {
            do {
                let capabilities = try await AIService.probeModelCapabilities(
                    baseURL: resolvedBaseURL,
                    apiKey: resolvedAPIKey,
                    model: modelId
                )

                await MainActor.run {
                    let updatedConfig = AIConfig(
                        isEnabled: isEnabled,
                        provider: provider,
                        baseURL: resolvedBaseURL,
                        apiKey: resolvedAPIKey,
                        model: modelId,
                        modelDisplayName: modelDisplayName,
                        customSystemPrompt: resolvedCustomSystemPrompt.isEmpty ? nil : resolvedCustomSystemPrompt,
                        capabilities: capabilities
                    )
                    commitAIConfig(updatedConfig)
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)

                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isSaving = false
                }
            }
        }
    }
}
