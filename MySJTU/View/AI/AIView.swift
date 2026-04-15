import SwiftUI

@MainActor
struct AIView: View {
    @AppStorage("aiConfig") private var aiConfig = AIConfig()
    let chatViewModel: AIChatViewModel
    @State private var isShowingSettings = false

    private var hasValidConfig: Bool {
        aiConfig.hasValidConfiguration
    }

    private var hasStoredConfig: Bool {
        aiConfig.hasStoredConfiguration
    }

    private var navigationSubtitle: String? {
        let trimmedDisplayName = aiConfig.modelDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }

        let trimmedModel = aiConfig.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedModel.isEmpty ? nil : trimmedModel
    }

    private var needsModelDisplayNameResolution: Bool {
        hasValidConfig
            && !(aiConfig.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && (aiConfig.modelDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasValidConfig {
                    AIChatScreen(config: aiConfig, viewModel: chatViewModel)
                        .id(aiConfig.conversationConfigurationIdentity)
                } else {
                    noConfigView
                }
            }
            .analyticsScreen(
                "ai_home",
                screenClass: "AIView",
                parameters: [
                    "ai_ready": hasValidConfig,
                    "has_stored_cfg": hasStoredConfig,
                    "ai_provider": aiConfig.provider?.rawValue ?? "none",
                    "tool_support": aiConfig.capabilities.supportsToolCalling ?? false
                ]
            )
            .modifier(AINavigationBarModifier(subtitle: navigationSubtitle))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isShowingSettings) {
                AISettingsView()
            }
            .task(id: aiConfig.rawValue) {
                await resolveModelDisplayNameIfNeeded()
            }
            .onAppear {
                chatViewModel.updateConfig(aiConfig)
            }
            .onChange(of: aiConfig.rawValue) { _, _ in
                chatViewModel.updateConfig(aiConfig)
            }
            .onChange(of: aiConfig.conversationConfigurationIdentity) { oldValue, newValue in
                guard oldValue != newValue else {
                    return
                }

                chatViewModel.resetConversation(using: aiConfig)
            }
            .toolbar {
                if hasValidConfig {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: startNewConversation) {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("新会话")
                    }
                }

                if hasStoredConfig {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: presentSettings) {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var noConfigView: some View {
        ContentUnavailableView {
            Label(
                "欢迎使用交课表 AI",
                systemImage: "sparkles"
            )
        } description: {
            Text(
                "需要配置 AI 服务提供商才能使用 AI 功能"
            )
        } actions: {
            Button(action: presentSettings) {
                Text("前往设置")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func presentSettings() {
        guard !isShowingSettings else {
            return
        }

        AnalyticsService.logEvent(
            "ai_settings_opened",
            parameters: [
                "ai_ready": hasValidConfig,
                "ai_provider": aiConfig.provider?.rawValue ?? "none"
            ]
        )
        dismissKeyboard()

        Task { @MainActor in
            await Task.yield()
            isShowingSettings = true
        }
    }

    private func startNewConversation() {
        AnalyticsService.logEvent(
            "ai_conversation_reset",
            parameters: [
                "ai_provider": aiConfig.provider?.rawValue ?? "none",
                "tool_support": aiConfig.capabilities.supportsToolCalling ?? false
            ]
        )
        dismissKeyboard()
        chatViewModel.resetConversation(using: aiConfig)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func resolveModelDisplayNameIfNeeded() async {
        guard needsModelDisplayNameResolution,
              let baseURL = aiConfig.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.isEmpty,
              let apiKey = aiConfig.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty,
              let modelId = aiConfig.model?.trimmingCharacters(in: .whitespacesAndNewlines),
              !modelId.isEmpty else {
            return
        }

        do {
            let models = try await AIService.fetchModels(baseURL: baseURL, apiKey: apiKey)
            guard let displayName = models.first(where: { $0.id == modelId })?.displayName else {
                return
            }

            let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDisplayName.isEmpty else {
                return
            }

            aiConfig.modelDisplayName = trimmedDisplayName
        } catch {
            // Keep the existing fallback title when the model list cannot be fetched.
        }
    }
}

private struct AINavigationBarModifier: ViewModifier {
    let subtitle: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let subtitle {
            content
                .navigationTitle("交课表 AI")
                .navigationSubtitle(subtitle)
        } else {
            content
                .navigationTitle("交课表 AI")
        }
    }
}

#Preview {
    AIView(chatViewModel: AIChatViewModel(config: AIConfig()))
}
