import SwiftUI

struct AIChatMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    struct AssistantActivity: Identifiable, Equatable {
        enum Kind: String, Equatable {
            case reasoning
            case toolStatus
        }

        let id: Int
        let kind: Kind
        let text: String
        let toolStatusFunctionName: String?
        let toolStatusCategory: AIToolCallCategory?
        let toolStatusInvocationKey: String?
        var startDate: Date?
        var endDate: Date?

        var duration: TimeInterval? {
            guard let start = startDate, let end = endDate else { return nil }
            return end.timeIntervalSince(start)
        }

        var toolStatusGroupKey: String? {
            guard kind == .toolStatus else {
                return nil
            }

            if let toolStatusFunctionName,
               !toolStatusFunctionName.isEmpty {
                return toolStatusFunctionName
            }

            if let toolStatusInvocationKey,
               !toolStatusInvocationKey.isEmpty {
                return toolStatusInvocationKey
            }

            return text
        }

        var toolStatusStatusCategoryKey: String {
            if text.hasPrefix("已调用") {
                return "invoked"
            }

            if text.hasPrefix("用户拒绝") {
                return "denied"
            }

            return "status"
        }

        var toolStatusCollapsedSummaryBaseText: String {
            guard let toolDisplayTitle = toolStatusDisplayTitle else {
                return text
            }

            switch toolStatusStatusCategoryKey {
            case "invoked":
                return "已调用“\(toolDisplayTitle)”"
            case "denied":
                return "用户拒绝了「\(toolDisplayTitle)」"
            default:
                return text
            }
        }

        private var toolStatusDisplayTitle: String? {
            toolStatusFunctionName.map { AIService.toolDisplayName(for: $0) }
        }
    }

    enum ContentSegment: Identifiable, Equatable {
        case activity(AssistantActivity)
        case visibleText(id: Int, text: String)

        var id: String {
            switch self {
            case .activity(let a): return "a\(a.id)"
            case .visibleText(let id, _): return "t\(id)"
            }
        }
    }

    let id: UUID
    let role: Role
    var text: String
    var feedbackText: String
    var assistantActivities: [AssistantActivity]
    var contentSegments: [ContentSegment]
    var errorText: String?
    var isStreaming: Bool

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        feedbackText: String = "",
        assistantActivities: [AssistantActivity] = [],
        contentSegments: [ContentSegment] = [],
        errorText: String? = nil,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.feedbackText = feedbackText
        self.assistantActivities = assistantActivities
        self.contentSegments = contentSegments
        self.errorText = errorText
        self.isStreaming = isStreaming
    }

    var hasFeedbackText: Bool {
        !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasErrorText: Bool {
        !(errorText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var reasoningText: String? {
        let reasoningSegments = assistantActivities
            .filter { $0.kind == .reasoning }
            .map(\.text)

        guard !reasoningSegments.isEmpty else {
            return nil
        }

        return reasoningSegments.joined(separator: "\n\n")
    }

    var toolStatusTexts: [String] {
        assistantActivities
            .filter { $0.kind == .toolStatus }
            .map(\.text)
    }

    var latestToolStatusText: String? {
        toolStatusTexts.last
    }

    var hasReasoningContent: Bool {
        reasoningText != nil
    }

    var hasToolStatus: Bool {
        !toolStatusTexts.isEmpty
    }

    var hasAssistantActivity: Bool {
        !assistantActivities.isEmpty
    }

    var activeReasoningActivityID: Int? {
        guard isStreaming,
              let trailingSegment = contentSegments.last,
              case .activity(let activity) = trailingSegment,
              activity.kind == .reasoning else {
            return nil
        }

        return activity.id
    }

    var isAwaitingPostToolContinuation: Bool {
        guard isStreaming,
              let trailingSegment = contentSegments.last,
              case .activity(let activity) = trailingSegment else {
            return false
        }

        return activity.kind == .toolStatus
    }

    mutating func reconcileReasoningTiming(
        previousActivities: [AssistantActivity],
        now: Date
    ) {
        let activeReasoningActivityID = activeReasoningActivityID

        for i in assistantActivities.indices {
            guard assistantActivities[i].kind == .reasoning else {
                continue
            }

            let activityID = assistantActivities[i].id

            if let previousActivity = previousActivities.first(where: {
                $0.id == activityID && $0.kind == .reasoning
            }) {
                assistantActivities[i].startDate = previousActivity.startDate
                assistantActivities[i].endDate = previousActivity.endDate
            }

            if assistantActivities[i].startDate == nil {
                assistantActivities[i].startDate = now
            }

            if activityID == activeReasoningActivityID {
                assistantActivities[i].endDate = nil
            } else if assistantActivities[i].endDate == nil {
                assistantActivities[i].endDate = now
            }
        }

        syncAssistantActivitySegments()
    }

    mutating func finalizeReasoningTiming(at now: Date) {
        for i in assistantActivities.indices {
            guard assistantActivities[i].kind == .reasoning,
                  assistantActivities[i].endDate == nil else {
                continue
            }

            assistantActivities[i].endDate = now
        }

        syncAssistantActivitySegments()
    }

    mutating func syncAssistantActivitySegments() {
        for i in contentSegments.indices {
            guard case .activity(let activity) = contentSegments[i],
                  let updatedActivity = assistantActivities.first(where: { $0.id == activity.id }) else {
                continue
            }

            contentSegments[i] = .activity(updatedActivity)
        }
    }
}

@MainActor
final class AIChatViewModel: ObservableObject {
    struct ToolPermissionRequest: Equatable {
        let toolName: String
        let toolDisplayName: String
        let baseURL: String
    }

    @Published private(set) var messages: [AIChatMessage] = []
    @Published private(set) var isStreaming = false
    @Published var scrollAnchor = 0
    @Published var pendingToolPermission: ToolPermissionRequest?
    @Published var showToolPermissionDialog = false
    @Published var presentedToolNavigationDestination: AIToolNavigationDestination?

    private var config: AIConfig
    private var streamingTask: Task<Void, Never>?
    private var toolPermissionContinuation: CheckedContinuation<AIToolPermissionDecision, Never>?

    var toolPermissionStore: Binding<AIToolPermissionStore>?

    init(config: AIConfig) {
        self.config = config
    }

    func updateConfig(_ config: AIConfig) {
        self.config = config
    }

    func resetConversation(using config: AIConfig) {
        cancelStreaming()
        updateConfig(config)
        messages.removeAll()
        presentedToolNavigationDestination = nil
        scrollAnchor += 1
    }

    func resolveToolPermission(_ decision: AIToolPermissionDecision) {
        if let request = pendingToolPermission {
            toolPermissionStore?.wrappedValue.recordTool(
                toolName: request.toolName,
                baseURL: request.baseURL,
                decision: decision
            )
        }
        toolPermissionContinuation?.resume(returning: decision)
        toolPermissionContinuation = nil
        pendingToolPermission = nil
        showToolPermissionDialog = false
    }

    private func requestToolPermission(
        toolName: String,
        toolDisplayName: String
    ) async -> AIToolPermissionDecision {
        let baseURL = config.baseURL ?? ""
        switch toolPermissionStore?.wrappedValue.policy(toolName: toolName, baseURL: baseURL) {
        case .alwaysAllow:
            return .allowOnce
        case .deny:
            return .deny
        case .askNextTime, .none:
            break
        }

        return await withCheckedContinuation { continuation in
            toolPermissionContinuation = continuation
            pendingToolPermission = ToolPermissionRequest(
                toolName: toolName,
                toolDisplayName: toolDisplayName,
                baseURL: baseURL
            )
            showToolPermissionDialog = true
        }
    }

    private func presentToolNavigation(_ destination: AIToolNavigationDestination) {
        presentedToolNavigationDestination = destination
    }

    func send(message: String) {
        guard !isStreaming else {
            return
        }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return
        }

        let userMessage = AIChatMessage(role: .user, text: trimmedMessage)
        let requestMessages = (messages + [userMessage]).map(\.conversationMessage)
        let assistantMessageID = UUID()

        messages.append(userMessage)
        messages.append(
            AIChatMessage(
                id: assistantMessageID,
                role: .assistant,
                text: "",
                isStreaming: true
            )
        )
        isStreaming = true
        scrollAnchor += 1

        streamingTask = Task { [config, weak self] in
            guard let self else {
                return
            }

            do {
                let reasoningDisplayFilter = AIReasoningDisplayFilter(
                    hidesReasoningContentByDefault: config.prefersReasoningContentHidden
                )
                let permissionHandler: AIService.ToolPermissionHandler? =
                    config.capabilities.supportsToolCalling == true
                    ? { @Sendable [self] toolName, toolDisplayName in
                        await self.requestToolPermission(
                            toolName: toolName,
                            toolDisplayName: toolDisplayName
                        )
                    }
                    : nil
                let navigationHandler: AIService.ToolNavigationHandler? =
                    config.capabilities.supportsToolCalling == true
                    ? { @Sendable [self] destination in
                        await self.presentToolNavigation(destination)
                    }
                    : nil

                let stream = try AIService.streamChat(
                    config: config,
                    messages: requestMessages,
                    toolPermissionHandler: permissionHandler,
                    toolNavigationHandler: navigationHandler
                )

                var lastRawText = ""
                for try await partialText in stream {
                    lastRawText = partialText
                    let presentation = reasoningDisplayFilter.presentation(from: partialText)
                    self.updateAssistantMessage(
                        id: assistantMessageID,
                        text: presentation.visibleText,
                        feedbackText: reasoningDisplayFilter.feedbackText(from: partialText),
                        assistantActivities: presentation.assistantActivities,
                        contentSegments: presentation.contentSegments,
                        isStreaming: true
                    )
                    self.scrollAnchor += 1
                    await Task.yield()
                }

                if !lastRawText.isEmpty {
                    let final = reasoningDisplayFilter.presentation(
                        from: lastRawText,
                        isStreamComplete: true
                    )
                    self.updateAssistantMessage(
                        id: assistantMessageID,
                        text: final.visibleText,
                        feedbackText: reasoningDisplayFilter.feedbackText(
                            from: lastRawText,
                            isStreamComplete: true
                        ),
                        assistantActivities: final.assistantActivities,
                        contentSegments: final.contentSegments,
                        isStreaming: true
                    )
                }

                self.finishStreamingMessage(id: assistantMessageID)
            } catch is CancellationError {
                self.endStreamingMessage(id: assistantMessageID, removeIfEmpty: true)
            } catch {
                self.presentAssistantErrorMessage(
                    id: assistantMessageID,
                    errorText: error.localizedDescription
                )
                self.endStreamingMessage(id: assistantMessageID, removeIfEmpty: false)
            }
        }
    }

    func cancelStreaming() {
        if toolPermissionContinuation != nil {
            toolPermissionContinuation?.resume(returning: .deny)
            toolPermissionContinuation = nil
            pendingToolPermission = nil
            showToolPermissionDialog = false
        }
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
    }

    private func updateAssistantMessage(
        id: UUID,
        text: String,
        feedbackText: String,
        assistantActivities: [AIChatMessage.AssistantActivity],
        contentSegments: [AIChatMessage.ContentSegment],
        isStreaming: Bool
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        var updatedMessage = messages[index]
        let oldActivities = updatedMessage.assistantActivities
        updatedMessage.text = text
        updatedMessage.feedbackText = feedbackText
        updatedMessage.assistantActivities = assistantActivities
        updatedMessage.contentSegments = contentSegments
        updatedMessage.isStreaming = isStreaming

        updatedMessage.reconcileReasoningTiming(
            previousActivities: oldActivities,
            now: Date()
        )

        messages[index] = updatedMessage
    }

    private func presentAssistantErrorMessage(id: UUID, errorText: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        let trimmedErrorText = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedErrorText = trimmedErrorText.isEmpty ? "发生未知错误，请稍后重试。" : trimmedErrorText
        var updatedMessage = messages[index]
        updatedMessage.feedbackText = ""
        updatedMessage.errorText = normalizedErrorText
        messages[index] = updatedMessage
        scrollAnchor += 1
    }

    private func finishStreamingMessage(id: UUID) {
        streamingTask = nil
        endStreamingMessage(id: id, removeIfEmpty: false)
    }

    private func endStreamingMessage(id: UUID, removeIfEmpty: Bool) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            let hasVisibleText = !messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if removeIfEmpty
                && !hasVisibleText
                && !messages[index].hasReasoningContent
                && !messages[index].hasToolStatus
                && !messages[index].hasErrorText {
                messages.remove(at: index)
            } else {
                var updatedMessage = messages[index]
                updatedMessage.isStreaming = false
                updatedMessage.finalizeReasoningTiming(at: Date())
                messages[index] = updatedMessage
            }
        }

        isStreaming = false
        scrollAnchor += 1
    }
}

extension AIConfig {
    var conversationConfigurationIdentity: String {
        [
            isEnabled ? "1" : "0",
            provider?.rawValue ?? "",
            model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        ].joined(separator: "\u{1F}")
    }
}

struct AIReasoningDisplayFilter {
    private static let openingTag = "<think>"
    private static let closingTag = "</think>"
    private static let toolStatusOpeningTag = "<tool_status>"
    private static let toolStatusClosingTag = "</tool_status>"

    let hidesReasoningContentByDefault: Bool

    struct Presentation {
        let visibleText: String
        let assistantActivities: [AIChatMessage.AssistantActivity]
        let contentSegments: [AIChatMessage.ContentSegment]
    }

    func presentation(from rawText: String, isStreamComplete: Bool = false) -> Presentation {
        let visibleTextWithoutHiddenReasoning = Self.extractPresentation(
            from: rawText,
            hidesReasoningContent: false,
            isStreamComplete: isStreamComplete
        ).visibleText
        let hidesReasoningContent = hidesReasoningContentByDefault
            || Self.hasLeadingThinkTag(in: visibleTextWithoutHiddenReasoning)

        return Self.extractPresentation(
            from: rawText,
            hidesReasoningContent: hidesReasoningContent,
            isStreamComplete: isStreamComplete
        )
    }

    func feedbackText(from rawText: String, isStreamComplete: Bool = false) -> String {
        Self.extractPresentation(
            from: rawText,
            hidesReasoningContent: true,
            isStreamComplete: isStreamComplete
        ).visibleText
    }

    private static func hasLeadingThinkTag(in text: String) -> Bool {
        let trimmedText = text.trimmingLeadingWhitespace
        return openingTag.hasPrefix(trimmedText) || trimmedText.hasPrefix(openingTag)
    }

    private static func extractPresentation(
        from text: String,
        hidesReasoningContent: Bool,
        isStreamComplete: Bool
    ) -> Presentation {
        var visibleText = ""
        var assistantActivities: [AIChatMessage.AssistantActivity] = []
        var contentSegments: [AIChatMessage.ContentSegment] = []
        var searchStart = text.startIndex
        var nextActivityID = 0
        var nextTextSegmentID = 0
        var hasSeenReasoningBlock = false
        var shouldCheckImpliedReasoning = false

        while searchStart < text.endIndex {
            if shouldCheckImpliedReasoning && hidesReasoningContent {
                shouldCheckImpliedReasoning = false
                let peekStart = skipWhitespace(in: text, from: searchStart)
                if peekStart < text.endIndex,
                   !startsWithTag(openingTag, in: text, from: peekStart),
                   !startsWithTag(toolStatusOpeningTag, in: text, from: peekStart) {
                    if let impliedCloseRange = text.range(
                        of: closingTag,
                        range: peekStart..<text.endIndex
                    ) {
                        appendActivity(
                            MarkerKind.reasoning.activity(
                                text: String(text[peekStart..<impliedCloseRange.lowerBound])
                            ),
                            to: &assistantActivities,
                            segments: &contentSegments,
                            nextID: &nextActivityID
                        )
                        searchStart = impliedCloseRange.upperBound
                        if visibleText.isEmpty {
                            searchStart = skipWhitespace(in: text, from: searchStart)
                        }
                        continue
                    } else if !isStreamComplete {
                        let remaining = trimmingTrailingPrefix(
                            ofAny: [closingTag, toolStatusOpeningTag],
                            from: String(text[peekStart...])
                        )
                        appendActivity(
                            MarkerKind.reasoning.activity(text: remaining),
                            to: &assistantActivities,
                            segments: &contentSegments,
                            nextID: &nextActivityID
                        )
                        return .init(
                            visibleText: visibleText,
                            assistantActivities: assistantActivities,
                            contentSegments: contentSegments
                        )
                    }
                }
            }

            guard let marker = nextMarker(
                in: text,
                from: searchStart,
                includesReasoning: hidesReasoningContent
            ) else {
                let remaining = trimmingTrailingPrefix(
                    ofAny: hidesReasoningContent
                        ? [openingTag, toolStatusOpeningTag]
                        : [toolStatusOpeningTag],
                    from: String(text[searchStart...])
                )
                appendVisibleSegment(remaining, to: &visibleText)
                appendTextSegment(remaining, to: &contentSegments, nextID: &nextTextSegmentID)
                return .init(
                    visibleText: visibleText,
                    assistantActivities: assistantActivities,
                    contentSegments: contentSegments
                )
            }

            let beforeMarker = String(text[searchStart..<marker.range.lowerBound])
            appendVisibleSegment(beforeMarker, to: &visibleText)
            appendTextSegment(beforeMarker, to: &contentSegments, nextID: &nextTextSegmentID)

            guard let closeRange = text.range(
                of: marker.kind.closingTag,
                range: marker.range.upperBound..<text.endIndex
            ) else {
                appendActivity(
                    marker.kind.activity(
                        text: trimmingTrailingPrefix(
                            of: marker.kind.closingTag,
                            from: String(text[marker.range.upperBound...])
                        )
                    ),
                    to: &assistantActivities,
                    segments: &contentSegments,
                    nextID: &nextActivityID
                )
                return .init(
                    visibleText: visibleText,
                    assistantActivities: assistantActivities,
                    contentSegments: contentSegments
                )
            }

            appendActivity(
                marker.kind.activity(
                    text: String(text[marker.range.upperBound..<closeRange.lowerBound])
                ),
                to: &assistantActivities,
                segments: &contentSegments,
                nextID: &nextActivityID
            )

            if marker.kind == .reasoning {
                hasSeenReasoningBlock = true
            } else if marker.kind == .toolStatus && hasSeenReasoningBlock {
                shouldCheckImpliedReasoning = true
            }

            searchStart = closeRange.upperBound
            if visibleText.isEmpty {
                searchStart = skipWhitespace(in: text, from: searchStart)
            }
        }

        return .init(
            visibleText: visibleText,
            assistantActivities: assistantActivities,
            contentSegments: contentSegments
        )
    }

    private static func appendVisibleSegment(_ segment: String, to visibleText: inout String) {
        if visibleText.isEmpty {
            visibleText += segment.trimmingLeadingWhitespace
        } else {
            visibleText += segment
        }
    }

    private static func appendActivity(
        _ activity: AIChatMessage.AssistantActivity?,
        to activities: inout [AIChatMessage.AssistantActivity],
        segments: inout [AIChatMessage.ContentSegment],
        nextID: inout Int
    ) {
        guard let activity else {
            return
        }

        let resolved = AIChatMessage.AssistantActivity(
            id: nextID,
            kind: activity.kind,
            text: activity.text,
            toolStatusFunctionName: activity.toolStatusFunctionName,
            toolStatusCategory: activity.toolStatusCategory,
            toolStatusInvocationKey: activity.toolStatusInvocationKey
        )
        activities.append(resolved)
        segments.append(.activity(resolved))
        nextID += 1
    }

    private static func appendTextSegment(
        _ segment: String,
        to segments: inout [AIChatMessage.ContentSegment],
        nextID: inout Int
    ) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        segments.append(.visibleText(id: nextID, text: trimmed))
        nextID += 1
    }

    private static func skipWhitespace(in text: String, from index: String.Index) -> String.Index {
        var currentIndex = index

        while currentIndex < text.endIndex,
              isWhitespace(text[currentIndex]) {
            currentIndex = text.index(after: currentIndex)
        }

        return currentIndex
    }

    private static func trimmingTrailingPrefix(of marker: String, from text: String) -> String {
        guard !text.isEmpty else {
            return text
        }

        let maxPrefixLength = min(text.count, marker.count - 1)
        guard maxPrefixLength > 0 else {
            return text
        }

        for prefixLength in stride(from: maxPrefixLength, through: 1, by: -1) {
            let suffix = String(text.suffix(prefixLength))
            if marker.hasPrefix(suffix) {
                return String(text.dropLast(prefixLength))
            }
        }

        return text
    }

    private static func trimmingTrailingPrefix(ofAny markers: [String], from text: String) -> String {
        markers.reduce(text) { partialResult, marker in
            trimmingTrailingPrefix(of: marker, from: partialResult)
        }
    }

    private static func normalizedReasoningText(from text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        return trimmedText
    }

    private static func normalizedToolStatusPayload(from text: String) -> ToolStatusPayload? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        if let data = trimmedText.data(using: .utf8),
           let payload = try? JSONDecoder().decode(ToolStatusPayload.self, from: data),
           !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return payload
        }

        return .init(text: trimmedText, functionName: nil, category: nil, invocationKey: nil)
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(\.properties.isWhitespace)
    }

    private static func startsWithTag(
        _ tag: String,
        in text: String,
        from index: String.Index
    ) -> Bool {
        guard index < text.endIndex else {
            return false
        }

        let remaining = String(text[index...])
        return remaining.hasPrefix(tag) || tag.hasPrefix(remaining)
    }

    private struct Marker {
        let kind: MarkerKind
        let range: Range<String.Index>
    }

    private struct ToolStatusPayload: Decodable {
        let text: String
        let functionName: String?
        let category: AIToolCallCategory?
        let invocationKey: String?

        enum CodingKeys: String, CodingKey {
            case text
            case functionName = "function_name"
            case category
            case invocationKey = "invocation_key"
        }
    }

    private enum MarkerKind {
        case reasoning
        case toolStatus

        var closingTag: String {
            switch self {
            case .reasoning:
                return AIReasoningDisplayFilter.closingTag
            case .toolStatus:
                return AIReasoningDisplayFilter.toolStatusClosingTag
            }
        }

        func activity(text: String) -> AIChatMessage.AssistantActivity? {
            switch self {
            case .reasoning:
                guard let normalizedText = AIReasoningDisplayFilter.normalizedReasoningText(from: text) else {
                    return nil
                }

                return .init(
                    id: 0,
                    kind: .reasoning,
                    text: normalizedText,
                    toolStatusFunctionName: nil,
                    toolStatusCategory: nil,
                    toolStatusInvocationKey: nil
                )
            case .toolStatus:
                guard let payload = AIReasoningDisplayFilter.normalizedToolStatusPayload(from: text) else {
                    return nil
                }

                return .init(
                    id: 0,
                    kind: .toolStatus,
                    text: payload.text,
                    toolStatusFunctionName: payload.functionName,
                    toolStatusCategory: payload.category ?? payload.functionName.flatMap { AIService.toolCategory(for: $0) },
                    toolStatusInvocationKey: payload.invocationKey
                )
            }
        }
    }

    private static func nextMarker(
        in text: String,
        from index: String.Index,
        includesReasoning: Bool
    ) -> Marker? {
        let toolStatusRange = text.range(of: toolStatusOpeningTag, range: index..<text.endIndex)
        let reasoningRange = includesReasoning
            ? text.range(of: openingTag, range: index..<text.endIndex)
            : nil

        switch (reasoningRange, toolStatusRange) {
        case let (reasoningRange?, toolStatusRange?):
            return reasoningRange.lowerBound < toolStatusRange.lowerBound
                ? Marker(kind: .reasoning, range: reasoningRange)
                : Marker(kind: .toolStatus, range: toolStatusRange)
        case let (reasoningRange?, nil):
            return Marker(kind: .reasoning, range: reasoningRange)
        case let (nil, toolStatusRange?):
            return Marker(kind: .toolStatus, range: toolStatusRange)
        case (nil, nil):
            return nil
        }
    }
}

private extension String {
    var trimmingLeadingWhitespace: String {
        String(drop { character in
            character.unicodeScalars.allSatisfy(\.properties.isWhitespace)
        })
    }
}

private extension AIChatMessage {
    var conversationMessage: AIService.ConversationMessage {
        AIService.ConversationMessage(
            role: role == .assistant ? .assistant : .user,
            content: text
        )
    }
}
