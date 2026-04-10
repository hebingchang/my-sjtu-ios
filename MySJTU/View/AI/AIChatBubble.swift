import SwiftUI

@MainActor
struct AIChatBubble: View {
    @Environment(\.colorScheme) private var colorScheme

    let message: AIChatMessage
    let userAvatarImage: UIImage?
    let isLoadingUserAvatar: Bool
    @State private var expandedReasoningActivityIDs: Set<Int> = []
    @State private var expandedToolStatusGroupIDs: Set<Int> = []
    @State private var streamingFeedbackTrigger = 0
    @State private var completionFeedbackTrigger = 0
    @State private var lastStreamingFeedbackAt = Date.distantPast

    private let avatarSize: CGFloat = 28
    private let avatarSpacing: CGFloat = 10
    private let messageRowSideInset: CGFloat = 40
    private let minimumStreamingFeedbackInterval: TimeInterval = 0.14

    private enum RenderedContentSegment: Identifiable, Equatable {
        case activity(AIChatMessage.AssistantActivity)
        case toolStatusGroup(ToolStatusGroup)
        case visibleText(id: Int, text: String)

        var id: String {
            switch self {
            case .activity(let activity):
                return "activity-\(activity.id)-\(activity.kind.rawValue)"
            case .toolStatusGroup(let group):
                return "tool-status-group-\(group.id)"
            case .visibleText(let id, _):
                return "text-\(id)"
            }
        }
    }

    private struct ToolStatusGroup: Identifiable, Equatable {
        let id: Int
        let activities: [AIChatMessage.AssistantActivity]

        var summaryText: String {
            guard let firstActivity = activities.first else {
                return ""
            }

            if activities.count == 1 {
                return firstActivity.text
            }

            let baseText: String
            if activities.allSatisfy({ $0.text == firstActivity.text }) {
                baseText = firstActivity.text
            } else {
                baseText = firstActivity.toolStatusCollapsedSummaryBaseText
            }

            return "\(baseText) x\(activities.count)"
        }
    }

    private var bubbleMarkdownStyle: AIMarkdownStyle {
        message.role == .assistant ? .assistantBubble : .userBubble
    }

    private var hasVisibleText: Bool {
        !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasErrorText: Bool {
        message.hasErrorText
    }

    private var isReasoningInProgress: Bool {
        guard message.role == .assistant && message.isStreaming else {
            return false
        }

        if message.activeReasoningActivityID != nil || message.isAwaitingPostToolContinuation {
            return true
        }

        return message.contentSegments.isEmpty && !hasVisibleText
    }

    private var hasProcessDetails: Bool {
        message.role == .assistant && message.hasAssistantActivity
    }

    private var shouldRender: Bool {
        switch message.role {
        case .user:
            return true
        case .assistant:
            return hasVisibleText || hasProcessDetails || isReasoningInProgress || hasErrorText
        }
    }

    private var reasoningPanelTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -8)),
            removal: .opacity
        )
    }

    private var assistantAccessoryTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: -3)),
            removal: .opacity
        )
    }

    private var bubbleMaxWidth: CGFloat {
        520
    }

    private var bubbleAlignment: Alignment {
        message.role == .assistant ? .leading : .trailing
    }

    private var assistantTrailingWidthReserve: CGFloat {
        messageRowSideInset + avatarSpacing + avatarSize
    }

    private var copyableBubbleText: String {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCopyBubbleText: Bool {
        !message.isStreaming && !copyableBubbleText.isEmpty
    }

    private var shouldAnimateStreamingText: Bool {
        message.role == .assistant && message.isStreaming
    }

    private var assistantStatusAnimationKey: String {
        let activityKey = message.assistantActivities
            .map { "\($0.kind.rawValue):\($0.text)" }
            .joined(separator: "\u{1F}")
        let errorKey = message.errorText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(activityKey)|\(isReasoningInProgress)|\(errorKey)"
    }

    private var renderedContentSegments: [RenderedContentSegment] {
        var renderedSegments: [RenderedContentSegment] = []
        var pendingToolStatuses: [AIChatMessage.AssistantActivity] = []

        func flushPendingToolStatuses() {
            guard !pendingToolStatuses.isEmpty else {
                return
            }

            if pendingToolStatuses.count == 1, let activity = pendingToolStatuses.first {
                renderedSegments.append(.activity(activity))
            } else if let firstActivity = pendingToolStatuses.first {
                renderedSegments.append(
                    .toolStatusGroup(
                        .init(id: firstActivity.id, activities: pendingToolStatuses)
                    )
                )
            }

            pendingToolStatuses.removeAll(keepingCapacity: true)
        }

        for segment in message.contentSegments {
            switch segment {
            case .activity(let activity):
                if activity.kind == .toolStatus {
                    if let lastPendingStatus = pendingToolStatuses.last,
                       lastPendingStatus.toolStatusGroupKey != activity.toolStatusGroupKey {
                        flushPendingToolStatuses()
                    }
                    pendingToolStatuses.append(activity)
                } else {
                    flushPendingToolStatuses()
                    renderedSegments.append(.activity(activity))
                }
            case .visibleText(let id, let text):
                flushPendingToolStatuses()
                renderedSegments.append(.visibleText(id: id, text: text))
            }
        }

        flushPendingToolStatuses()
        return renderedSegments
    }

    private var showsStreamingIndicator: Bool {
        message.isStreaming && hasVisibleText
    }

    private var assistantBubbleBackgroundStyle: AnyShapeStyle {
        if colorScheme == .dark {
            AnyShapeStyle(.thinMaterial)
        } else {
            AnyShapeStyle(Color(uiColor: .systemBackground))
        }
    }

    private var assistantBubbleBorderColor: Color {
        if colorScheme == .dark {
            Color.white.opacity(0.08)
        } else {
            Color.black.opacity(0.08)
        }
    }

    private var assistantBubbleShadowColor: Color {
        if colorScheme == .dark {
            .clear
        } else {
            Color.black.opacity(0.05)
        }
    }

    private var avatarBackgroundColor: Color {
        if colorScheme == .dark {
            Color(uiColor: .secondarySystemGroupedBackground)
        } else {
            Color(uiColor: .systemBackground)
        }
    }

    private var avatarBorderColor: Color {
        if colorScheme == .dark {
            Color.white.opacity(0.1)
        } else {
            Color.black.opacity(0.08)
        }
    }

    private var avatarShadowColor: Color {
        if colorScheme == .dark {
            .clear
        } else {
            Color.black.opacity(0.05)
        }
    }

    @ViewBuilder
    var body: some View {
        if shouldRender {
            Group {
                if message.role == .assistant {
                    assistantMessageRow
                } else {
                    userMessageRow
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .assistant ? .leading : .trailing)
            .onChange(of: message.feedbackText) { oldText, newText in
                triggerStreamingFeedbackIfNeeded(from: oldText, to: newText)
            }
            .onChange(of: message.isStreaming) { wasStreaming, isStreaming in
                triggerCompletionFeedbackIfNeeded(wasStreaming: wasStreaming, isStreaming: isStreaming)
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.35), trigger: streamingFeedbackTrigger)
            .sensoryFeedback(.success, trigger: completionFeedbackTrigger)
        }
    }

    private var assistantMessageRow: some View {
        HStack(alignment: .top, spacing: 0) {
            assistantMessageContent
                .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear
                .frame(width: assistantTrailingWidthReserve, height: 1)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var assistantMessageContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if renderedContentSegments.isEmpty {
                if isReasoningInProgress {
                    reasoningProgressView
                        .transition(assistantAccessoryTransition)
                }
            } else {
                ForEach(renderedContentSegments) { segment in
                    switch segment {
                    case .activity(let activity):
                        reasoningTimelineItem(activity)
                            .id("\(activity.id)-\(activity.kind.rawValue)")
                            .transition(assistantAccessoryTransition)
                    case .toolStatusGroup(let group):
                        toolStatusGroupView(group)
                            .id("tool-status-group-\(group.id)")
                            .transition(assistantAccessoryTransition)
                    case .visibleText(_, let segmentText):
                        textSegmentBubble(text: segmentText)
                    }
                }

                if isReasoningInProgress, !isLastRenderedSegmentReasoning {
                    reasoningProgressView
                        .transition(assistantAccessoryTransition)
                }
            }

            if let errorText = message.errorText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !errorText.isEmpty {
                assistantErrorBox(text: errorText)
                    .transition(assistantAccessoryTransition)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: assistantStatusAnimationKey)
    }

    private var isLastRenderedSegmentReasoning: Bool {
        if case .activity(let activity) = renderedContentSegments.last,
           activity.kind == .reasoning {
            return true
        }
        return false
    }

    private func isLastTextSegment(_ segmentText: String) -> Bool {
        guard case .visibleText(_, let lastText) = message.contentSegments.last else {
            return false
        }
        return lastText == segmentText
    }

    private func textSegmentBubble(text segmentText: String) -> some View {
        let isLast = isLastTextSegment(segmentText)
        let showIndicator = isLast && showsStreamingIndicator

        return ViewThatFits(in: .horizontal) {
            textSegmentBubbleBody(text: segmentText, showIndicator: showIndicator)
                .fixedSize(horizontal: true, vertical: false)

            textSegmentBubbleBody(text: segmentText, showIndicator: showIndicator)
                .frame(maxWidth: bubbleMaxWidth, alignment: bubbleAlignment)
        }
        .contextMenu {
            if canCopyBubbleText {
                Button("复制全文", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = copyableBubbleText
                }
            }
        }
    }

    private func textSegmentBubbleBody(text segmentText: String, showIndicator: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldAnimateStreamingText {
                AIMarkdownContentView(
                    text: segmentText,
                    style: bubbleMarkdownStyle
                )
                .phaseAnimator([0.72 as Double, 1.0], trigger: segmentText) { content, opacity in
                    content.opacity(opacity)
                } animation: { _ in
                    .easeOut(duration: 0.2)
                }
            } else {
                AIMarkdownContentView(
                    text: segmentText,
                    style: bubbleMarkdownStyle
                )
            }

            if showIndicator {
                streamingIndicator
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -2)),
                            removal: .opacity
                        )
                    )
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showIndicator)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            bubbleShape
                .fill(assistantBubbleBackgroundStyle)
        }
        .overlay {
            bubbleShape
                .stroke(assistantBubbleBorderColor, lineWidth: 1)
        }
        .shadow(
            color: assistantBubbleShadowColor,
            radius: 10,
            x: 0,
            y: 4
        )
    }

    private var userMessageRow: some View {
        HStack(alignment: .top, spacing: avatarSpacing) {
            Spacer(minLength: messageRowSideInset)
            bubbleCopyTarget
            userAvatar
        }
    }

    @ViewBuilder
    private func reasoningTimelineItem(_ activity: AIChatMessage.AssistantActivity) -> some View {
        switch activity.kind {
        case .reasoning:
            let isActivelyReasoning = message.activeReasoningActivityID == activity.id
            let hasReasoningText = hasVisibleReasoningText(activity.text)
            let isExpanded = isReasoningExpanded(activity.id)

            VStack(alignment: .leading, spacing: 6) {
                if hasReasoningText || !isActivelyReasoning {
                    reasoningToggleButton(
                        activityID: activity.id,
                        isExpanded: isExpanded,
                        showsSpinner: isActivelyReasoning,
                        duration: activity.duration
                    )
                } else {
                    reasoningProgressView
                }

                if isExpanded {
                    expandedReasoningContent(activity.text)
                        .transition(reasoningPanelTransition)
                }
            }
            .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        case .toolStatus:
            toolStatusView(activity.text)
        }
    }

    private func reasoningToggleButton(
        activityID: Int,
        isExpanded: Bool,
        showsSpinner: Bool,
        duration: TimeInterval? = nil
    ) -> some View {
        Button(action: {
            toggleReasoning(activityID: activityID)
        }) {
            HStack(spacing: showsSpinner ? 6 : 4) {
                if showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(showsSpinner ? "正在思考" : reasoningCompletedText(duration: duration))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func reasoningCompletedText(duration: TimeInterval?) -> String {
        guard let duration, duration >= 1 else {
            return "已思考"
        }

        let seconds = Int(duration)
        if seconds < 60 {
            return "已思考 \(seconds) 秒"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            if remainingSeconds == 0 {
                return "已思考 \(minutes) 分钟"
            }
            return "已思考 \(minutes) 分 \(remainingSeconds) 秒"
        }
    }

    private func toolStatusView(_ text: String) -> some View {
        toolStatusCapsule(text: text)
    }

    private func toolStatusGroupView(_ group: ToolStatusGroup) -> some View {
        let isExpanded = isToolStatusGroupExpanded(group.id)

        return VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                toggleToolStatusGroup(groupID: group.id)
            }) {
                toolStatusCapsule(
                    text: group.summaryText,
                    trailingSystemImage: isExpanded ? "chevron.up" : "chevron.down"
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(group.activities) { activity in
                        toolStatusView(activity.text)
                    }
                }
                .padding(.leading, 4)
                .transition(reasoningPanelTransition)
            }
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
    }

    private func toolStatusCapsule(
        text: String,
        trailingSystemImage: String? = nil
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wrench.adjustable.fill")
                .font(.caption2)
            Text(text)
                .lineLimit(2)
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.caption2.weight(.semibold))
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: Capsule()
        )
    }

    private var reasoningProgressView: some View {
        reasoningStatusLabel("正在思考", showsSpinner: true)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func reasoningStatusLabel(_ title: String, showsSpinner: Bool) -> some View {
        HStack(spacing: 6) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
            }

            Text(title)
        }
    }

    private func expandedReasoningContent(_ reasoningText: String) -> some View {
        AIMarkdownContentView(
            text: reasoningText,
            style: .reasoning
        )
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func assistantErrorBox(text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)

                Text("出错了")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .background(
            Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.12),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.orange.opacity(colorScheme == .dark ? 0.32 : 0.24), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var bubbleCopyTarget: some View {
        if canCopyBubbleText {
            bubbleContent
                .contentShape(bubbleShape)
                .contextMenu(menuItems: bubbleCopyMenu)
        } else {
            bubbleContent
        }
    }

    private var bubbleContent: some View {
        ViewThatFits(in: .horizontal) {
            bubbleBody
                .fixedSize(horizontal: true, vertical: false)

            bubbleBody
                .frame(maxWidth: bubbleMaxWidth, alignment: bubbleAlignment)
        }
    }

    private var bubbleBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasVisibleText {
                bubbleTextContent
            }

            if showsStreamingIndicator {
                streamingIndicator
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -2)),
                            removal: .opacity
                        )
                    )
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showsStreamingIndicator)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            bubbleShape
                .fill(message.role == .assistant ? assistantBubbleBackgroundStyle : AnyShapeStyle(Color.accentColor.gradient))
        }
        .overlay {
            if message.role == .assistant {
                bubbleShape
                    .stroke(assistantBubbleBorderColor, lineWidth: 1)
            }
        }
        .shadow(
            color: message.role == .assistant ? assistantBubbleShadowColor : .clear,
            radius: 10,
            x: 0,
            y: 4
        )
    }

    private var streamingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("生成中")
                .font(.caption)
        }
        .foregroundStyle(
            message.role == .assistant
                ? AnyShapeStyle(.secondary)
                : AnyShapeStyle(.white.opacity(0.85))
        )
    }

    @ViewBuilder
    private var bubbleTextContent: some View {
        if shouldAnimateStreamingText {
            AIMarkdownContentView(
                text: message.text,
                style: bubbleMarkdownStyle
            )
            .phaseAnimator([0.72 as Double, 1.0], trigger: message.text) { content, opacity in
                content.opacity(opacity)
            } animation: { _ in
                .easeOut(duration: 0.2)
            }
        } else {
            AIMarkdownContentView(
                text: message.text,
                style: bubbleMarkdownStyle
            )
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if message.role == .assistant {
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 24,
                style: .continuous
            )
        } else {
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 24,
                topTrailingRadius: 8,
                style: .continuous
            )
        }
    }

    private func isReasoningExpanded(_ activityID: Int) -> Bool {
        expandedReasoningActivityIDs.contains(activityID)
    }

    private func isToolStatusGroupExpanded(_ groupID: Int) -> Bool {
        expandedToolStatusGroupIDs.contains(groupID)
    }

    private func hasVisibleReasoningText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func toggleReasoning(activityID: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if isReasoningExpanded(activityID) {
                expandedReasoningActivityIDs.remove(activityID)
            } else {
                expandedReasoningActivityIDs.insert(activityID)
            }
        }
    }

    private func toggleToolStatusGroup(groupID: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if isToolStatusGroupExpanded(groupID) {
                expandedToolStatusGroupIDs.remove(groupID)
            } else {
                expandedToolStatusGroupIDs.insert(groupID)
            }
        }
    }

    private func triggerStreamingFeedbackIfNeeded(from oldText: String, to newText: String) {
        guard shouldAnimateStreamingText else {
            return
        }

        let oldVisibleText = oldText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newVisibleText = newText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard newVisibleText.count > oldVisibleText.count else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastStreamingFeedbackAt) >= minimumStreamingFeedbackInterval else {
            return
        }

        lastStreamingFeedbackAt = now
        streamingFeedbackTrigger += 1
    }

    private func triggerCompletionFeedbackIfNeeded(wasStreaming: Bool, isStreaming: Bool) {
        guard message.role == .assistant else {
            return
        }

        if isStreaming {
            lastStreamingFeedbackAt = .distantPast
            return
        }

        guard wasStreaming, message.hasFeedbackText else {
            return
        }

        completionFeedbackTrigger += 1
    }

    @ViewBuilder
    private func bubbleCopyMenu() -> some View {
        if canCopyBubbleText {
            Button("复制全文", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = copyableBubbleText
            }
        }
    }

    private var userAvatar: some View {
        ZStack {
            avatarBackgroundColor

            if let userAvatarImage {
                Image(uiImage: userAvatarImage)
                    .resizable()
                    .scaledToFill()
            } else if isLoadingUserAvatar {
                ProgressView()
            } else {
                userAvatarPlaceholder
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(avatarBorderColor, lineWidth: 1)
        }
        .shadow(color: avatarShadowColor, radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private var userAvatarPlaceholder: some View {
        if let placeholderImage = UIImage(named: "avatar_placeholder") {
            Image(uiImage: placeholderImage)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "person.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

enum AIChatUserAvatarLoadState {
    case idle
    case loading
    case loaded(String, UIImage)
    case failed
}

@MainActor
final class AIChatAvatarImageLoader {
    static let shared = AIChatAvatarImageLoader()

    private let cache = NSCache<NSURL, UIImage>()

    func image(for url: URL) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode,
              let image = UIImage(data: data) else {
            throw URLError(.badServerResponse)
        }

        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}
