import SwiftUI

@MainActor
struct AIChatScreen: View {
    private static let bottomAnchor = "ai-chat-bottom"
    private static let bottomAutoScrollThreshold: CGFloat = 60

    let config: AIConfig

    @AppStorage("accounts") private var accounts: [WebAuthAccount] = []
    @AppStorage("aiToolPermissions") private var toolPermissionStore = AIToolPermissionStore()
    @ObservedObject private var viewModel: AIChatViewModel
    @State private var draft = ""
    @State private var isNearBottom = true
    @State private var isUserControllingScroll = false
    @State private var shouldAutoScrollToBottom = true
    @State private var userAvatarLoadState: AIChatUserAvatarLoadState = .idle
    @FocusState private var isInputFocused: Bool

    init(config: AIConfig, viewModel: AIChatViewModel) {
        self.config = config
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    private var currentJAccount: WebAuthAccount? {
        accounts.first { $0.provider == .jaccount && $0.status == .connected }
            ?? accounts.first { $0.provider == .jaccount }
    }

    private var currentUserAvatarURL: String? {
        [currentJAccount?.user.avatar, currentJAccount?.user.photo]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private var userAvatarImage: UIImage? {
        if case .loaded(_, let image) = userAvatarLoadState {
            return image
        }

        return nil
    }

    private var isLoadingUserAvatar: Bool {
        if case .loading = userAvatarLoadState {
            return true
        }

        return false
    }

    private var quickPromptTitles: [String] {
        if config.capabilities.supportsToolCalling == true {
            return [
                "明天有课吗",
                "现在第几周了",
                "在下院找个自习教室"
            ]
        } else {
            return [
                "帮我翻译这段话",
                "帮我写邮件",
                "解释这个概念"
            ]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if viewModel.messages.isEmpty {
                            emptyState
                                .frame(maxWidth: .infinity)
                                .padding(.top, 56)
                                .padding(.bottom, 24)
                        } else {
                            ForEach(viewModel.messages) { message in
                                AIChatBubble(
                                    message: message,
                                    userAvatarImage: userAvatarImage,
                                    isLoadingUserAvatar: isLoadingUserAvatar
                                )
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            guard abs(value.translation.height) > abs(value.translation.width) else {
                                return
                            }

                            if !isUserControllingScroll {
                                isUserControllingScroll = true
                                shouldAutoScrollToBottom = false
                            }
                        }
                        .onEnded { _ in
                            isUserControllingScroll = false
                            if isNearBottom {
                                shouldAutoScrollToBottom = true
                            }
                        }
                )
                .onScrollPhaseChange { _, newPhase, _ in
                    if isUserControlledScrollPhase(newPhase) {
                        isUserControllingScroll = true
                        shouldAutoScrollToBottom = false
                    } else if newPhase == .idle {
                        isUserControllingScroll = false
                        if isNearBottom {
                            shouldAutoScrollToBottom = true
                        }
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    isNearBottom(in: geometry)
                } action: { _, newIsNearBottom in
                    isNearBottom = newIsNearBottom
                    if newIsNearBottom && !isUserControllingScroll {
                        shouldAutoScrollToBottom = true
                    }
                }
                .onChange(of: viewModel.scrollAnchor) { _, _ in
                    guard shouldAutoScrollToBottom else {
                        return
                    }
                    scrollToBottom(using: proxy, animated: !viewModel.isStreaming)
                }
                .onChange(of: isInputFocused) { _, isFocused in
                    guard isFocused else {
                        return
                    }
                    syncBottomPositionAfterViewportChange(using: proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                    syncBottomPositionAfterViewportChange(using: proxy)
                }
                .onAppear {
                    guard isInputFocused else {
                        return
                    }

                    syncBottomPositionAfterViewportChange(using: proxy)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .analyticsScreen(
            "ai_chat",
            screenClass: "AIChatScreen",
            parameters: [
                "ai_provider": config.provider?.rawValue ?? "none",
                "tool_support": config.capabilities.supportsToolCalling ?? false,
                "msg_count": viewModel.messages.count
            ]
        )
        .task(id: currentUserAvatarURL) {
            await loadUserAvatarIfNeeded()
        }
        .onChange(of: config.apiKey) { _, _ in
            viewModel.updateConfig(config)
        }
        .safeAreaInset(edge: .bottom) {
            AIComposerView(
                text: $draft,
                isStreaming: viewModel.isStreaming,
                isFocused: $isInputFocused,
                onSend: {
                    sendMessage()
                },
                onStop: {
                    AnalyticsService.logEvent(
                        "ai_stream_cancelled",
                        parameters: [
                            "ai_provider": config.provider?.rawValue ?? "none"
                        ]
                    )
                    viewModel.cancelStreaming()
                }
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background {
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color(uiColor: .systemGroupedBackground).opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .onDisappear {
            isInputFocused = false
            dismissKeyboard()
        }
        .onAppear {
            viewModel.toolPermissionStore = $toolPermissionStore
        }
        .onChange(of: viewModel.pendingToolPermission) { _, request in
            guard let request else {
                return
            }

            AnalyticsService.logEvent(
                "ai_tool_permission",
                parameters: [
                    "status": "prompted",
                    "tool_name": request.toolName,
                    "provider": AIToolPermissionStore.providerDisplayName(for: request.baseURL)
                ]
            )
        }
        .alert(
            "工具调用请求",
            isPresented: $viewModel.showToolPermissionDialog
        ) {
            if viewModel.pendingToolPermission != nil {
                Button("始终允许") {
                    if let request = viewModel.pendingToolPermission {
                        AnalyticsService.logEvent(
                            "ai_tool_permission",
                            parameters: [
                                "status": "always_allow",
                                "tool_name": request.toolName,
                                "provider": AIToolPermissionStore.providerDisplayName(for: request.baseURL)
                            ]
                        )
                    }
                    viewModel.resolveToolPermission(.alwaysAllow)
                }
                Button("允许一次") {
                    if let request = viewModel.pendingToolPermission {
                        AnalyticsService.logEvent(
                            "ai_tool_permission",
                            parameters: [
                                "status": "allow_once",
                                "tool_name": request.toolName,
                                "provider": AIToolPermissionStore.providerDisplayName(for: request.baseURL)
                            ]
                        )
                    }
                    viewModel.resolveToolPermission(.allowOnce)
                }
                Button("不允许", role: .cancel) {
                    if let request = viewModel.pendingToolPermission {
                        AnalyticsService.logEvent(
                            "ai_tool_permission",
                            parameters: [
                                "status": "denied",
                                "tool_name": request.toolName,
                                "provider": AIToolPermissionStore.providerDisplayName(for: request.baseURL)
                            ]
                        )
                    }
                    viewModel.resolveToolPermission(.deny)
                }
            }
        } message: {
            if let request = viewModel.pendingToolPermission {
                Text(
                    "来自 \(AIToolPermissionStore.providerDisplayName(for: request.baseURL)) 的模型请求调用“\(request.toolDisplayName)”，是否允许？"
                )
            }
        }
        .sheet(item: $viewModel.presentedToolNavigationDestination) { destination in
            toolNavigationSheet(destination)
        }
    }

    private func loadUserAvatarIfNeeded() async {
        guard let urlString = currentUserAvatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else {
            userAvatarLoadState = .idle
            return
        }

        if case .loaded(let loadedURLString, _) = userAvatarLoadState, loadedURLString == urlString {
            return
        }

        userAvatarLoadState = .loading

        guard let avatarURL = URL(string: urlString) else {
            userAvatarLoadState = .failed
            return
        }

        do {
            let image = try await AIChatAvatarImageLoader.shared.image(for: avatarURL)
            guard !Task.isCancelled else {
                return
            }
            userAvatarLoadState = .loaded(urlString, image)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            userAvatarLoadState = .failed
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.14))
                    .frame(width: 80, height: 80)

                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Text("开始新的 AI 对话")
                    .font(.title3.weight(.semibold))

                Text(config.capabilities.supportsToolCalling == true ? "当前模型支持工具调用，可以向您请求授权使用更多信息。" : "当前模型不支持工具调用，仅能提供简单的聊天。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Text("快速提问")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        ForEach(quickPromptTitles, id: \.self) { title in
                            AIChatInfoChip(
                                title: title,
                                isEnabled: !viewModel.isStreaming
                            ) {
                                sendQuickPrompt(title)
                            }
                        }
                    }

                    VStack(spacing: 10) {
                        ForEach(quickPromptTitles, id: \.self) { title in
                            AIChatInfoChip(
                                title: title,
                                isEnabled: !viewModel.isStreaming
                            ) {
                                sendQuickPrompt(title)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
    }

    private func sendMessage(source: String = "composer") {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else {
            return
        }

        AnalyticsService.logEvent(
            "ai_message_sent",
            parameters: [
                "source": source,
                "len_bucket": AnalyticsService.messageLengthBucket(for: trimmedDraft),
                "ai_provider": config.provider?.rawValue ?? "none",
                "tool_support": config.capabilities.supportsToolCalling ?? false
            ]
        )
        shouldAutoScrollToBottom = true
        draft = ""
        viewModel.updateConfig(config)
        viewModel.send(message: trimmedDraft)
        isInputFocused = true
    }

    private func sendQuickPrompt(_ prompt: String) {
        guard !viewModel.isStreaming else {
            return
        }

        draft = prompt
        sendMessage(source: "quick_prompt")
    }

    @ViewBuilder
    private func toolNavigationSheet(_ destination: AIToolNavigationDestination) -> some View {
        switch destination {
        case .jAccountAccount:
            NavigationStack {
                AccountView(provider: .jaccount)
                    .navigationTitle("jAccount 账户")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        guard animated else {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            return
        }

        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    private func syncBottomPositionAfterViewportChange(using proxy: ScrollViewProxy) {
        guard shouldAutoScrollToBottom else {
            return
        }

        Task { @MainActor in
            await Task.yield()

            guard shouldAutoScrollToBottom else {
                return
            }

            scrollToBottom(using: proxy, animated: !viewModel.isStreaming)
        }
    }

    private func isNearBottom(in geometry: ScrollGeometry) -> Bool {
        distanceToBottom(in: geometry) <= Self.bottomAutoScrollThreshold
    }

    private func distanceToBottom(in geometry: ScrollGeometry) -> CGFloat {
        max(0, geometry.contentSize.height - geometry.visibleRect.maxY)
    }

    private func isUserControlledScrollPhase(_ phase: ScrollPhase) -> Bool {
        switch phase {
        case .tracking, .interacting, .decelerating:
            return true
        case .idle, .animating:
            return false
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

@MainActor
struct AIChatInfoChip: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

@MainActor
struct AIComposerView: View {
    @Binding var text: String

    let isStreaming: Bool
    let isFocused: FocusState<Bool>.Binding
    let onSend: @MainActor () -> Void
    let onStop: @MainActor () -> Void

    private let composerCornerRadius: CGFloat = 28

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("给 AI 发送消息", text: $text, axis: .vertical)
                .focused(isFocused)
                .lineLimit(1...6)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.plain)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .onSubmit(handleSubmit)

            Button(action: handleActionButtonTap) {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(buttonForegroundStyle)
                    .frame(width: 34, height: 34)
                    .background(buttonBackgroundStyle, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isStreaming && !canSend)
            .accessibilityLabel(isStreaming ? "停止生成" : "发送消息")
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous))
        .onTapGesture(perform: focusInput)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: composerCornerRadius, style: .continuous))
    }

    private func handleSubmit() {
        guard !isStreaming, canSend else {
            return
        }

        onSend()
    }

    private func handleActionButtonTap() {
        if isStreaming {
            onStop()
        } else {
            onSend()
        }
    }

    private func focusInput() {
        isFocused.wrappedValue = true
    }

    private var buttonForegroundStyle: AnyShapeStyle {
        if isStreaming || canSend {
            AnyShapeStyle(.white)
        } else {
            AnyShapeStyle(.secondary)
        }
    }

    private var buttonBackgroundStyle: AnyShapeStyle {
        if isStreaming {
            AnyShapeStyle(Color.orange.gradient)
        } else if canSend {
            AnyShapeStyle(Color.accentColor.gradient)
        } else {
            AnyShapeStyle(Color(uiColor: .tertiarySystemFill))
        }
    }
}
