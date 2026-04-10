//
//  AIService.swift
//  MySJTU
//
//  Created by boar on 2026/04/03.
//

import Foundation
import Alamofire

enum AIToolCallCategory: String, Codable, Sendable {
    case query = "查询"
    case write = "写入"
    case navigation = "导航"
    case notification = "通知"
}

enum AIToolNavigationDestination: String, Codable, Sendable, Identifiable {
    case jAccountAccount = "jaccount_account"

    var id: String { rawValue }
}

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case custom
    case chatSJTU

    var id: Self { self }

    var displayName: String {
        switch self {
        case .custom: return "自定义"
        case .chatSJTU: return "chat.sjtu.edu.cn"
        }
    }
}

struct AIModelCapabilities: Codable, Equatable {
    var supportsToolCalling: Bool?
    var supportsResponsesAPI: Bool?

    init(
        supportsToolCalling: Bool? = nil,
        supportsResponsesAPI: Bool? = nil
    ) {
        self.supportsToolCalling = supportsToolCalling
        self.supportsResponsesAPI = supportsResponsesAPI
    }

    var hasDetectedCapabilities: Bool {
        supportsToolCalling != nil || supportsResponsesAPI != nil
    }
}

struct AIConfig: Codable, RawRepresentable {
    var isEnabled: Bool
    var provider: AIProvider?
    var baseURL: String?
    var apiKey: String?
    var model: String?
    var modelDisplayName: String?
    var customSystemPrompt: String?
    var capabilities: AIModelCapabilities

    init(
        isEnabled: Bool = false,
        provider: AIProvider? = nil,
        baseURL: String? = nil,
        apiKey: String? = nil,
        model: String? = nil,
        modelDisplayName: String? = nil,
        customSystemPrompt: String? = nil,
        capabilities: AIModelCapabilities = .init()
    ) {
        self.isEnabled = isEnabled
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.modelDisplayName = modelDisplayName
        self.customSystemPrompt = customSystemPrompt
        self.capabilities = capabilities
    }

    init(
        provider: AIProvider,
        baseURL: String,
        apiKey: String,
        model: String? = nil,
        modelDisplayName: String? = nil,
        customSystemPrompt: String? = nil,
        capabilities: AIModelCapabilities = .init(),
        isEnabled: Bool = true
    ) {
        self.init(
            isEnabled: isEnabled,
            provider: provider,
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            modelDisplayName: modelDisplayName,
            customSystemPrompt: customSystemPrompt,
            capabilities: capabilities
        )
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case provider
        case baseURL
        case apiKey
        case model
        case modelDisplayName
        case customSystemPrompt
        case capabilities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let provider = try container.decodeIfPresent(AIProvider.self, forKey: .provider)
        let baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
        let apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        let hasLegacyConfig = provider != nil
            || !(baseURL?.isEmpty ?? true)
            || !(apiKey?.isEmpty ?? true)

        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.modelDisplayName = try container.decodeIfPresent(String.self, forKey: .modelDisplayName)
        self.customSystemPrompt = try container.decodeIfPresent(String.self, forKey: .customSystemPrompt)
        self.capabilities = try container.decodeIfPresent(AIModelCapabilities.self, forKey: .capabilities) ?? .init()
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? hasLegacyConfig
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(baseURL, forKey: .baseURL)
        try container.encodeIfPresent(apiKey, forKey: .apiKey)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(modelDisplayName, forKey: .modelDisplayName)
        try container.encodeIfPresent(customSystemPrompt, forKey: .customSystemPrompt)
        try container.encode(capabilities, forKey: .capabilities)
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIConfig.self, from: data)
        else {
            return nil
        }
        self = result
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return result
    }

    var hasValidConfiguration: Bool {
        guard isEnabled,
              provider != nil,
              let baseURL, !baseURL.isEmpty,
              let apiKey, !apiKey.isEmpty,
              let model, !model.isEmpty
        else {
            return false
        }
        return true
    }

    var hasStoredConfiguration: Bool {
        provider != nil
            || !(baseURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var prefersReasoningContentHidden: Bool {
        let trimmedModel = model?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard !trimmedModel.isEmpty else {
            return false
        }

        let normalizedModel = trimmedModel.replacingOccurrences(of: "_", with: "-")
        if normalizedModel.contains("reason") || normalizedModel.contains("thinking") {
            return true
        }

        let tokens = normalizedModel
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let reasoningTokens = ["qwq", "r1", "o1", "o3", "o4"]

        return tokens.contains { token in
            reasoningTokens.contains { reasoningToken in
                token == reasoningToken || token.hasPrefix(reasoningToken)
            }
        }
    }
}

enum AIToolPermissionDecision: Sendable {
    case alwaysAllow
    case allowOnce
    case deny
}

enum AIToolPermissionPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case alwaysAllow
    case askNextTime
    case deny

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alwaysAllow:
            return "始终允许"
        case .askNextTime:
            return "下次询问"
        case .deny:
            return "不允许"
        }
    }
}

struct AIToolPermissionStore: Codable, RawRepresentable, Equatable {
    /// baseURL → [toolName: policy]
    var tools: [String: [String: AIToolPermissionPolicy]]

    private static let currentSchemaVersion = 3

    init(tools: [String: [String: AIToolPermissionPolicy]] = [:]) {
        self.tools = tools
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tools
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        if schemaVersion >= Self.currentSchemaVersion {
            self.tools = try container.decodeIfPresent(
                [String: [String: AIToolPermissionPolicy]].self,
                forKey: .tools
            ) ?? [:]
        } else {
            let legacyTools = try container.decodeIfPresent([String: [String: Bool]].self, forKey: .tools) ?? [:]
            self.tools = Self.migrateLegacyTools(legacyTools, schemaVersion: schemaVersion)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(tools, forKey: .tools)
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode(AIToolPermissionStore.self, from: data)
        else { return nil }
        self = result
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else { return "{}" }
        return result
    }

    struct ProviderEntry: Identifiable {
        let baseURL: String
        let tools: [(name: String, policy: AIToolPermissionPolicy)]
        var id: String { baseURL }
    }

    var isEmpty: Bool {
        tools.values.allSatisfy(\.isEmpty)
    }

    var providerEntries: [ProviderEntry] {
        tools
            .compactMap { entry -> (key: String, value: [String: AIToolPermissionPolicy])? in
                let filteredTools = entry.value.filter { toolEntry in
                    AIService.toolRequiresUserAuthorization(for: toolEntry.key)
                }

                guard !filteredTools.isEmpty else {
                    return nil
                }

                return (key: entry.key, value: filteredTools)
            }
            .sorted { $0.key < $1.key }
            .map { entry in
                ProviderEntry(
                    baseURL: entry.key,
                    tools: entry.value
                        .sorted { $0.key < $1.key }
                        .map { (name: $0.key, policy: $0.value) }
                )
            }
    }

    var totalToolCount: Int {
        providerEntries.reduce(0) { $0 + $1.tools.count }
    }

    func policy(toolName: String, baseURL: String) -> AIToolPermissionPolicy? {
        guard AIService.toolRequiresUserAuthorization(for: toolName) else {
            return nil
        }
        return tools[baseURL]?[toolName]
    }

    func decision(toolName: String, baseURL: String) -> AIToolPermissionDecision? {
        switch policy(toolName: toolName, baseURL: baseURL) {
        case .alwaysAllow:
            return .alwaysAllow
        case .deny:
            return .deny
        case .askNextTime, .none:
            return nil
        }
    }

    mutating func recordTool(toolName: String, baseURL: String, decision: AIToolPermissionDecision) {
        switch decision {
        case .alwaysAllow:
            setPolicy(.alwaysAllow, toolName: toolName, baseURL: baseURL)
        case .deny:
            setPolicy(.deny, toolName: toolName, baseURL: baseURL)
        case .allowOnce:
            setPolicy(.askNextTime, toolName: toolName, baseURL: baseURL)
        }
    }

    mutating func setPolicy(_ policy: AIToolPermissionPolicy, toolName: String, baseURL: String) {
        guard AIService.toolRequiresUserAuthorization(for: toolName) else {
            removeTool(toolName: toolName, baseURL: baseURL)
            return
        }

        var providerTools = tools[baseURL] ?? [:]
        providerTools[toolName] = policy
        tools[baseURL] = providerTools
    }

    mutating func removeTool(toolName: String, baseURL: String) {
        tools[baseURL]?.removeValue(forKey: toolName)
        if tools[baseURL]?.isEmpty == true {
            tools.removeValue(forKey: baseURL)
        }
    }

    mutating func resetAuthorizedPermissions() {
        let authorizedTools = tools.flatMap { baseURL, providerTools in
            providerTools.compactMap { entry in
                entry.value == .alwaysAllow
                    ? (baseURL: baseURL, toolName: entry.key)
                    : nil
            }
        }

        for authorizedTool in authorizedTools {
            removeTool(toolName: authorizedTool.toolName, baseURL: authorizedTool.baseURL)
        }
    }

    private static func migrateLegacyTools(
        _ legacyTools: [String: [String: Bool]],
        schemaVersion: Int
    ) -> [String: [String: AIToolPermissionPolicy]] {
        legacyTools.reduce(into: [:]) { result, providerEntry in
            let migratedTools = providerEntry.value.reduce(into: [String: AIToolPermissionPolicy]()) { toolResult, toolEntry in
                let policy: AIToolPermissionPolicy

                switch schemaVersion {
                case 2:
                    policy = toolEntry.value ? .alwaysAllow : .deny
                default:
                    // Legacy schema 1 stored `false` for any non-persistent allow.
                    policy = toolEntry.value ? .alwaysAllow : .askNextTime
                }

                toolResult[toolEntry.key] = policy
            }

            if !migratedTools.isEmpty {
                result[providerEntry.key] = migratedTools
            }
        }
    }

    static func toolDisplayName(for functionName: String) -> String {
        AIService.toolDisplayName(for: functionName)
    }

    static func providerDisplayName(for baseURL: String) -> String {
        if baseURL == AIService.chatSJTUBaseURL {
            return "chat.sjtu.edu.cn"
        }
        if let url = URL(string: baseURL), let host = url.host {
            return host
        }
        return baseURL
    }
}

enum AIServiceError: Error, LocalizedError {
    case noJAccountSession
    case tokenNotFound
    case loginFailed(String)
    case missingConfiguration
    case invalidBaseURL
    case invalidModel
    case missingToolCallResult
    case requestFailed(String)
    case invalidStreamPayload

    var errorDescription: String? {
        switch self {
        case .noJAccountSession:
            return "没有有效的 jAccount 会话"
        case .tokenNotFound:
            return "未能获取到 token"
        case .loginFailed(let reason):
            return "登录失败：\(reason)"
        case .missingConfiguration:
            return "AI 配置不完整"
        case .invalidBaseURL:
            return "Base URL 格式无效"
        case .invalidModel:
            return "模型 ID 不能为空"
        case .missingToolCallResult:
            return "模型没有返回工具调用结果"
        case .requestFailed(let reason):
            return "请求失败：\(reason)"
        case .invalidStreamPayload:
            return "流式响应格式无效"
        }
    }
}

struct AIService {
    typealias ToolPermissionHandler = @Sendable (
        _ toolName: String,
        _ toolDisplayName: String
    ) async -> AIToolPermissionDecision
    typealias ToolNavigationHandler = @Sendable (
        _ destination: AIToolNavigationDestination
    ) async -> Void

    static let chatSJTUBaseURL = "https://chat.sjtu.edu.cn/api"
    static let chatSJTULoginURL = "https://chat.sjtu.edu.cn/oauth/jaccount/login"
    fileprivate static let reasoningOpeningTag = "<think>"
    fileprivate static let reasoningClosingTag = "</think>"
    static let toolStatusOpeningTag = "<tool_status>"
    static let toolStatusClosingTag = "</tool_status>"
    private static var beijingTimeZone: TimeZone {
        TimeZone(identifier: "Asia/Shanghai")
            ?? TimeZone(secondsFromGMT: 8 * 60 * 60)
            ?? .current
    }

    private static func currentBeijingDateTimeString(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = beijingTimeZone
        formatter.dateFormat = "yyyy年M月d日 EEEE HH:mm:ss"
        return formatter.string(from: now)
    }

    private static func assistantSystemPrompt(
        customSystemPrompt: String? = nil,
        supportsToolCalling: Bool? = nil,
        now: Date = .now
    ) -> String {
        let basePrompt = """
你是一个面向“交课表” iOS app 用户的 AI 助手。

当前北京时间：\(currentBeijingDateTimeString(now: now))。

当用户问题需要查询 app 当前数据源、学期、周次等应用内数据时，优先调用可用工具，不要凭记忆猜测。
当用户明确要求打开 app 内页面、登录入口或账户设置页时，优先调用对应的导航工具，而不是只用文字描述操作步骤。
当用户询问 Canvas 待办、Canvas 作业或近期需要提交的内容时，优先调用 Canvas 待办查询工具；若工具返回未启用 Canvas，应明确告知用户前往 jAccount 账户页授权打开。
当用户要求创建提醒、定时通知、稍后提醒或闹钟式提醒时，优先调用通知工具创建本地推送通知。
当用户要求查询当前还有哪些提醒，或要求取消、删除尚未触发的提醒时，优先调用通知查询或删除工具。

你的回答应遵循以下规则：

1. 默认尽可能简短。
2. 只有在确有必要时才展开说明；能用一句话说清，就不要说两句。
3. 默认不使用 markdown。
4. 只有在内容表达明显受益时，才使用列表、标题、表格、引用、代码块等 markdown 语法。
5. 若包含数学公式、变量表达式或数学推导，行内公式必须放在 $...$ 中，独立公式必须放在 $$...$$ 中。
6. 不要输出未包裹在 $ 或 $$ 中的 LaTeX 公式。
7. 回答优先直接、清晰、自然，避免冗长铺垫、客套话和重复表达。
8. 不确定时明确说明不确定，不要编造。
9. 用户没有要求细节时，只给结论或最必要的信息。
10. 用户要求展开、解释、分步骤、举例时，再提供更完整内容。
11. 默认跟随用户语言；若用户使用中文，则用中文回答；若用户使用英文，则用英文回答。
12. 除非用户明确要求，否则不要主动输出长篇结构化内容。
13. 除非用户明确要求，否则不要主动给出多种方案；优先给最合适的一个答案。
14. 当问题有明确可执行结果时，先给结果，再补充必要说明。
15. 保持礼貌，但避免过度寒暄。

为降低幻觉与错误信息，额外遵循以下规则：

16. 仅在有足够依据时才给出明确事实性结论；依据不足时，直接说明“我不确定”或“信息不足”。
17. 不要把猜测、推断、经验性判断表述成确定事实；若是推测，必须明确标注为“推测”或“可能”。
18. 当用户提供的信息不完整、存在歧义或前提可能有误时，优先指出缺失点或前提问题，再作答。
19. 不要虚构来源、引用、数据、论文、机构、人物观点、产品功能、系统能力或历史事件。
20. 不要假装看到了用户未提供的文件、图片、网页、上下文或外部信息。
21. 不要声称执行了实际上未执行的操作，不要声称已经验证、查询、访问、打开、读取或调用了未实际完成的内容。
22. 涉及时间敏感、易变化或高风险信息时，若无法确认最新状态，应明确说明可能过时。
23. 涉及医疗、法律、金融、安全、账号、系统配置等高风险建议时，只提供谨慎、通用、低风险的信息；不确定时明确提示用户进一步核实。
24. 若用户陈述与常识或已知信息冲突，不要直接附和；应温和指出可能存在误差。
25. 若问题超出你的知识边界、上下文范围或可确认范围，允许直接回答“我不知道”。
26. 优先保证事实准确，其次再追求回答完整与流畅。
27. 当多个解释都可能成立时，不要擅自选定其一；应简要说明存在多种可能。
28. 若必须基于不完整信息给出帮助，先说明假设条件，再在该假设下回答。
29. 不要为了显得自然或完整而补造细节。
30. 用户要求“只给答案”时，也不能牺牲事实准确性；如无法确定，仍应明确说明无法确定。

在可用工具存在时，遵循以下工具使用原则：

31. 只要工具能够帮助核实事实、读取用户数据、获取最新信息或完成操作，优先使用工具，而不是仅凭记忆作答。
32. 对于时间敏感、会变化、需要精确数据、依赖用户个人数据或外部状态的问题，应优先通过工具获取信息。
33. 当用户的问题涉及最新消息、天气、价格、日程、邮件、文件、数据库、网页内容、账号状态、库存、位置、设备状态或其他动态信息时，默认先调用合适的工具。
34. 当工具可以直接读取原始信息时，优先读取原始信息，不要基于片段线索自行脑补。
35. 能通过工具确认的事实，不要用猜测代替确认。
36. 若工具调用失败、返回不足或不可用，应明确说明限制，而不是假装已经查到结果。
37. 不要声称“已查询”“已验证”“已读取”或“已打开”任何内容，除非你确实完成了对应工具调用。
38. 当用户要求执行操作时，优先使用工具完成；若无法执行，再明确说明原因。
39. 当工具结果与模型记忆冲突时，优先以工具返回结果为准；如仍有不确定性，应明确指出冲突。
40. 在不影响简洁性的前提下，可基于工具结果直接给出结论；无需展示冗余过程。
41. 若用户问题可以仅凭常识稳定回答，且不依赖最新信息、外部数据或用户私有信息，则无需为小事过度调用工具。
42. 工具的目标是提升准确性、减少幻觉、补足上下文，而不是制造冗长过程；能查则查，查完简洁回答。
43. 当需要基于工具结果推断时，应将“工具返回的事实”和“基于这些事实的推断”区分表达。
44. 若多个工具都可用，优先选择最直接、最可靠、最接近原始数据源的工具。
45. 当用户提供的内容与工具结果不一致时，应礼貌指出差异，并以更可验证的信息为准。
46. 除非用户要求详细过程，否则不必展开描述工具调用细节，只需给出结论和必要说明。
47. 即使用户拒绝了你的工具调用请求，也不要用猜测代替确认，而是告诉用户拒绝工具请求无法获取信息。

输出风格目标：
简洁、准确、克制、自然。

总原则：
宁可少答、保留判断并先查证，也不要编造、脑补或伪装确定性。
"""

        let toolCallingCapabilityPrompt: String
        if supportsToolCalling == false {
            toolCallingCapabilityPrompt = """
当前模型能力限制：
1. 当前模型不支持 tool call，不能调用任何工具。
2. 当用户的问题依赖工具、最新信息、应用内数据、账号状态或执行操作时，必须明确说明当前模型不支持工具调用，因此无法直接查询或执行。
3. 遇到这类情况时，应提示用户前往 AI 设置，更换为支持工具调用的模型后再试。
4. 不要假装已经调用工具，也不要把本应通过工具获取的信息表述成已经核实的事实。
"""
        } else {
            toolCallingCapabilityPrompt = ""
        }

        let trimmedCustomPrompt = customSystemPrompt?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedCustomPrompt.isEmpty, toolCallingCapabilityPrompt.isEmpty {
            return basePrompt
        }

        var promptSections = [basePrompt]
        if !toolCallingCapabilityPrompt.isEmpty {
            promptSections.append(toolCallingCapabilityPrompt)
        }
        if !trimmedCustomPrompt.isEmpty {
            promptSections.append("""
以下是用户提供的自定义提示词。它位于系统提示词的最后；在不与以上规则冲突时，请尽量遵循：
\(trimmedCustomPrompt)
""")
        }

        return promptSections.joined(separator: "\n\n")
    }

    private static let maxToolCallingRounds = 36
    private static let acceptedStatusCodes = 200..<300

    struct ReasoningTaggedTextAccumulator {
        private(set) var text = ""
        private var isReasoningBlockOpen = false

        @discardableResult
        mutating func appendReasoning(_ delta: String) -> String? {
            guard !delta.isEmpty else {
                return nil
            }

            if !isReasoningBlockOpen {
                text += AIService.reasoningOpeningTag
                isReasoningBlockOpen = true
            }

            return AIService.append(delta, to: &text)
        }

        @discardableResult
        mutating func appendVisibleText(_ delta: String) -> String? {
            guard !delta.isEmpty else {
                return nil
            }

            _ = finalizeReasoningIfNeeded()
            return AIService.append(delta, to: &text)
        }

        @discardableResult
        mutating func finalizeReasoningIfNeeded() -> String? {
            guard isReasoningBlockOpen else {
                return nil
            }

            isReasoningBlockOpen = false
            return AIService.append(AIService.reasoningClosingTag, to: &text)
        }
    }

    struct AIModelInfo: Codable, Identifiable {
        var id: String
        var name: String?
        var object: String?
        var created: TimeInterval?
        var ownedBy: String?

        var displayName: String {
            name ?? id
        }

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case object
            case created
            case ownedBy = "owned_by"
        }
    }

    enum ConversationRole: Sendable {
        case system
        case user
        case assistant
    }

    struct ConversationMessage: Equatable, Sendable {
        var role: ConversationRole
        var content: String
    }

    static func fetchModels(baseURL: String, apiKey: String) async throws -> [AIModelInfo] {
        let configuration = try makeAPIConfiguration(baseURL: baseURL, apiKey: apiKey)
        let request = try makeRequest(
            url: configuration.url(path: "models"),
            method: .get,
            apiKey: configuration.apiKey
        )

        let data = try await performDataRequest(
            AppAF.session.request(request).validate(statusCode: acceptedStatusCodes)
        )

        let result = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return result.data.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    static func streamChat(
        config: AIConfig,
        messages: [ConversationMessage],
        toolPermissionHandler: ToolPermissionHandler? = nil,
        toolNavigationHandler: ToolNavigationHandler? = nil
    ) throws -> AsyncThrowingStream<String, Error> {
        guard let baseURL = config.baseURL else {
            throw AIServiceError.missingConfiguration
        }

        let apiKey = try resolveAPIKey(for: config)

        let trimmedModel = config.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedModel.isEmpty else {
            throw AIServiceError.invalidModel
        }

        let sanitizedMessages = messages.compactMap(\.sanitized)
        let promptMessages = [
            ConversationMessage(
                role: .system,
                content: assistantSystemPrompt(
                    customSystemPrompt: config.customSystemPrompt,
                    supportsToolCalling: config.capabilities.supportsToolCalling
                )
            )
        ] + sanitizedMessages
        let configuration = try makeAPIConfiguration(baseURL: baseURL, apiKey: apiKey)

        if config.capabilities.supportsToolCalling == true {
            return toolCallingChat(
                with: configuration,
                model: trimmedModel,
                messages: promptMessages,
                toolPermissionHandler: toolPermissionHandler,
                toolNavigationHandler: toolNavigationHandler
            )
        }

        if config.capabilities.supportsResponsesAPI == true {
            return try streamResponsesChat(
                with: configuration,
                model: trimmedModel,
                messages: promptMessages
            )
        } else {
            return try streamCompletionsChat(
                with: configuration,
                model: trimmedModel,
                messages: promptMessages
            )
        }
    }

    static func probeModelCapabilities(baseURL: String, apiKey: String, model: String) async throws -> AIModelCapabilities {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw AIServiceError.invalidModel
        }

        let configuration = try makeAPIConfiguration(baseURL: baseURL, apiKey: apiKey)

        async let supportsResponsesAPI = probeResponsesAPISupport(with: configuration, model: trimmedModel)
        async let supportsToolCalling = probeToolCallingSupport(with: configuration, model: trimmedModel)

        let resolvedSupportsResponsesAPI = await supportsResponsesAPI
        let resolvedSupportsToolCalling = await supportsToolCalling

        return AIModelCapabilities(
            supportsToolCalling: resolvedSupportsToolCalling,
            supportsResponsesAPI: resolvedSupportsResponsesAPI
        )
    }

    static func refreshChatSJTUToken(cookies: [HTTPCookie]) async throws -> String {
        cookies.forEach { cookie in
            AppAF.cookieStorage.setCookie(cookie)
        }
        let response = await AppAF.session.request(chatSJTULoginURL)
            .serializingData()
            .response

        if let error = response.error {
            throw unwrapTransportError(error)
        }

        if let tokenCookie = chatSJTUTokenCookie() {
            return tokenCookie.value
        }

        guard let httpResponse = response.response else {
            throw AIServiceError.loginFailed("无效的响应")
        }

        if httpResponse.statusCode != 200 {
            throw AIServiceError.loginFailed("HTTP \(httpResponse.statusCode)")
        }

        throw AIServiceError.tokenNotFound
    }

    static func refreshChatSJTUToken(cookies: [Cookie]) async throws -> String {
        try await refreshChatSJTUToken(cookies: cookies.compactMap(\.httpCookie))
    }

    private static func chatSJTUTokenCookie() -> HTTPCookie? {
        let storages = [
            AppAF.cookieStorage,
            HTTPCookieStorage.shared
        ]

        for storage in storages {
            guard let cookies = storage.cookies else { continue }
            if let tokenCookie = cookies.last(where: {
                $0.name == "token" && $0.domain.contains("chat.sjtu.edu.cn")
            }) {
                return tokenCookie
            }
        }

        return nil
    }

    private static func resolveAPIKey(for config: AIConfig) throws -> String {
        if config.provider == .chatSJTU,
           let token = chatSJTUTokenCookie()?.value.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }

        if let apiKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            return apiKey
        }

        throw AIServiceError.missingConfiguration
    }

    private static func streamResponsesChat(
        with configuration: AIAPIConfiguration,
        model: String,
        messages: [ConversationMessage]
    ) throws -> AsyncThrowingStream<String, Error> {
        let eventHandler: @Sendable (Data, inout String) throws -> String? = { data, accumulatedText in
            try processResponsesEvent(data: data, accumulatedText: &accumulatedText)
        }

        let request = try makeStreamRequest(
            url: configuration.url(path: "responses"),
            method: .post,
            apiKey: configuration.apiKey,
            body: ResponsesCreateRequest(
                input: messages.map(\.responsesInputMessage),
                model: model,
                store: false,
                stream: true
            )
        )

        return streamSSEText(
            request: AF.streamRequest(request).validate(statusCode: acceptedStatusCodes),
            eventHandler: eventHandler
        )
    }

    private static func streamCompletionsChat(
        with configuration: AIAPIConfiguration,
        model: String,
        messages: [ConversationMessage]
    ) throws -> AsyncThrowingStream<String, Error> {
        let chunkStream = try streamChatCompletionChunks(
            with: configuration,
            model: model,
            messages: messages.map(\.chatCompletionMessage)
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                var accumulatedText = ReasoningTaggedTextAccumulator()

                do {
                    for try await chunk in chunkStream {
                        if let updatedText = try processChatCompletionsChunk(
                            chunk,
                            accumulatedText: &accumulatedText
                        ) {
                            continuation.yield(updatedText)
                        }
                    }

                    if let finalizedText = accumulatedText.finalizeReasoningIfNeeded() {
                        continuation.yield(finalizedText)
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func streamChatCompletionChunks(
        with configuration: AIAPIConfiguration,
        model: String,
        messages: [ChatCompletionsRequest.Message],
        toolChoice: ChatCompletionsRequest.ToolChoice? = nil,
        tools: [ChatCompletionsRequest.Tool]? = nil
    ) throws -> AsyncThrowingStream<ChatCompletionStreamChunk, Error> {
        let eventHandler: @Sendable (Data) throws -> ChatCompletionStreamChunk? = { data in
            try decodeChatCompletionStreamChunk(from: data)
        }

        let request = try makeStreamRequest(
            url: configuration.url(path: "chat/completions"),
            method: .post,
            apiKey: configuration.apiKey,
            body: ChatCompletionsRequest(
                messages: messages,
                model: model,
                store: false,
                stream: true,
                toolChoice: toolChoice,
                tools: tools
            )
        )

        return streamSSEEvents(
            request: AF.streamRequest(request).validate(statusCode: acceptedStatusCodes),
            eventHandler: eventHandler
        )
    }

    private static func streamSSEText(
        request: DataStreamRequest,
        eventHandler: @escaping @Sendable (_ payload: Data, _ accumulatedText: inout String) throws -> String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEEventParser()
                var accumulatedText = ""
                let streamTask = request.streamTask()

                do {
                    for await stream in streamTask.streamingData(automaticallyCancelling: false) {
                        switch stream.event {
                        case .stream(.success(let data)):
                            let payloads = try parser.append(data)
                            for payload in payloads {
                                if let updatedText = try eventHandler(payload, &accumulatedText) {
                                    continuation.yield(updatedText)
                                }
                            }
                        case .complete(let completion):
                            let payloads = try parser.finish()
                            for payload in payloads {
                                if let updatedText = try eventHandler(payload, &accumulatedText) {
                                    continuation.yield(updatedText)
                                }
                            }

                            if let error = completion.error {
                                throw mapStreamError(error, response: completion.response)
                            }

                            continuation.finish()
                            return
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                request.cancel()
                task.cancel()
            }
        }
    }

    private static func streamSSEEvents<Event>(
        request: DataStreamRequest,
        eventHandler: @escaping @Sendable (_ payload: Data) throws -> Event?
    ) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEEventParser()
                let streamTask = request.streamTask()

                do {
                    for await stream in streamTask.streamingData(automaticallyCancelling: false) {
                        switch stream.event {
                        case .stream(.success(let data)):
                            let payloads = try parser.append(data)
                            for payload in payloads {
                                if let event = try eventHandler(payload) {
                                    continuation.yield(event)
                                }
                            }
                        case .complete(let completion):
                            let payloads = try parser.finish()
                            for payload in payloads {
                                if let event = try eventHandler(payload) {
                                    continuation.yield(event)
                                }
                            }

                            if let error = completion.error {
                                throw mapStreamError(error, response: completion.response)
                            }

                            continuation.finish()
                            return
                        }
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                request.cancel()
                task.cancel()
            }
        }
    }

    private static func toolCallingChat(
        with configuration: AIAPIConfiguration,
        model: String,
        messages: [ConversationMessage],
        toolPermissionHandler: ToolPermissionHandler?,
        toolNavigationHandler: ToolNavigationHandler?
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await completeChatWithTools(
                        with: configuration,
                        model: model,
                        messages: messages,
                        onUpdate: { updatedText in
                            continuation.yield(updatedText)
                        },
                        toolPermissionHandler: toolPermissionHandler,
                        toolNavigationHandler: toolNavigationHandler
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func completeChatWithTools(
        with configuration: AIAPIConfiguration,
        model: String,
        messages: [ConversationMessage],
        onUpdate: @escaping @Sendable (String) -> Void,
        toolPermissionHandler: ToolPermissionHandler?,
        toolNavigationHandler: ToolNavigationHandler?
    ) async throws -> String {
        var requestMessages = messages.map(\.chatCompletionMessage)
        var committedText = ""

        for _ in 0..<maxToolCallingRounds {
            var roundState = StreamingToolRoundState()
            let chunkStream = try streamChatCompletionChunks(
                with: configuration,
                model: model,
                messages: requestMessages,
                tools: ToolRegistry.availableChatTools
            )

            for try await chunk in chunkStream {
                if try roundState.apply(chunk) {
                    onUpdate(committedText + roundState.previewText)
                }
            }

            if roundState.finalizePreviewIfNeeded() {
                onUpdate(committedText + roundState.previewText)
            }

            if roundState.hasToolCalls {
                let toolCalls = try roundState.finalizedToolCalls()
                requestMessages.append(
                    .init(
                        role: "assistant",
                        content: roundState.assistantMessageContent,
                        toolCalls: toolCalls.map(\.requestToolCall)
                    )
                )

                committedText += roundState.previewText

                for toolCall in toolCalls {
                    let toolResult: String
                    let requiresUserAuthorization = toolRequiresUserAuthorization(
                        for: toolCall.function.name
                    )

                    if requiresUserAuthorization,
                       let handler = toolPermissionHandler {
                        let displayName = AIToolPermissionStore.toolDisplayName(for: toolCall.function.name)
                        let decision = await handler(toolCall.function.name, displayName)

                        if decision == .deny {
                            committedText = appendToolStatus(
                                toolPermissionDeniedStatusPayload(
                                    for: toolCall,
                                    toolDisplayName: displayName
                                ),
                                to: committedText
                            )
                            onUpdate(committedText)
                            toolResult = encodeToolExecutionError(
                                .init(error: "用户拒绝了此工具调用。请不要重试此工具，直接根据已有信息回答用户。")
                            )
                            requestMessages.append(
                                .toolResponse(toolCallID: toolCall.id, content: toolResult)
                            )
                            continue
                        }
                    }

                    committedText = appendToolStatus(
                        await toolInvocationStatusPayload(for: toolCall),
                        to: committedText
                    )
                    onUpdate(committedText)

                    toolResult = await executeToolCall(
                        toolCall,
                        toolNavigationHandler: toolNavigationHandler
                    )
                    requestMessages.append(
                        .toolResponse(
                            toolCallID: toolCall.id,
                            content: toolResult
                        )
                    )
                }

                continue
            }

            guard roundState.hasResolvedAssistantMessage else {
                throw AIServiceError.requestFailed("模型没有返回可用的消息内容")
            }

            committedText += roundState.previewText
            onUpdate(committedText)
            return committedText
        }

        throw AIServiceError.requestFailed("工具调用轮次过多")
    }

    static func processResponsesEvent(
        data: Data,
        accumulatedText: inout String
    ) throws -> String? {
        if data == SSEEventParser.donePayload {
            return nil
        }

        do {
            let event = try JSONDecoder().decode(ResponsesStreamEvent.self, from: data)
            switch event.type {
            case "response.output_text.delta":
                guard let delta = event.delta else { return nil }
                return append(delta, to: &accumulatedText)
            case "response.output_text.done":
                guard let text = event.text else { return nil }
                return replace(with: text, current: &accumulatedText)
            case "response.refusal.delta":
                guard let delta = event.delta else { return nil }
                return append(delta, to: &accumulatedText)
            case "response.refusal.done":
                guard let refusal = event.refusal else { return nil }
                return replace(with: refusal, current: &accumulatedText)
            case "error", "response.failed":
                throw AIServiceError.requestFailed(event.errorMessage ?? "服务端返回了错误事件")
            default:
                return nil
            }
        } catch {
            if let finalText = try decodeResponsesOutputText(from: data) {
                return replace(with: finalText, current: &accumulatedText)
            }
            if let message = extractAPIErrorMessage(from: data) {
                throw AIServiceError.requestFailed(message)
            }
            throw error
        }
    }

    private static func processChatCompletionsEvent(
        data: Data,
        accumulatedText: inout ReasoningTaggedTextAccumulator
    ) throws -> String? {
        guard let chunk = try decodeChatCompletionStreamChunk(from: data) else {
            return nil
        }
        return try processChatCompletionsChunk(chunk, accumulatedText: &accumulatedText)
    }

    private static func decodeChatCompletionStreamChunk(
        from data: Data
    ) throws -> ChatCompletionStreamChunk? {
        if data == SSEEventParser.donePayload {
            return nil
        }

        do {
            return try JSONDecoder().decode(ChatCompletionStreamChunk.self, from: data)
        } catch {
            if let message = extractAPIErrorMessage(from: data) {
                throw AIServiceError.requestFailed(message)
            }
            throw error
        }
    }

    private static func processChatCompletionsChunk(
        _ chunk: ChatCompletionStreamChunk,
        accumulatedText: inout ReasoningTaggedTextAccumulator
    ) throws -> String? {
        var latestText: String?

        for choice in chunk.choices {
            guard let delta = choice.delta else { continue }

            if let reasoning = delta.reasoningTextDelta {
                latestText = accumulatedText.appendReasoning(reasoning)
            }
            if let content = delta.content {
                latestText = accumulatedText.appendVisibleText(content)
            }
            if let refusal = delta.refusal {
                latestText = accumulatedText.appendVisibleText(refusal)
            }
        }

        return latestText
    }

    private static func testResponsesAPISupport(with configuration: AIAPIConfiguration, model: String) async throws {
        let stream = try streamResponsesChat(
            with: configuration,
            model: model,
            messages: [.init(role: .user, content: "Reply with OK.")]
        )

        var hasReceivedText = false
        for try await partialText in stream {
            if partialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                hasReceivedText = true
                break
            }
        }

        if !hasReceivedText {
            throw AIServiceError.requestFailed("Responses API 没有返回可用的流式文本")
        }
    }

    private static func probeResponsesAPISupport(with configuration: AIAPIConfiguration, model: String) async -> Bool {
        do {
            try await testResponsesAPISupport(with: configuration, model: model)
            return true
        } catch {
            return false
        }
    }

    private static func probeToolCallingSupport(with configuration: AIAPIConfiguration, model: String) async -> Bool {
        do {
            try await testToolCallingSupport(with: configuration, model: model)
            return true
        } catch {
            return false
        }
    }

    private static func testToolCallingSupport(with configuration: AIAPIConfiguration, model: String) async throws {
        let response = try await performChatCompletion(
            with: configuration,
            model: model,
            messages: [
                .init(
                    role: "user",
                    content: "Call the \(ToolRegistry.capabilityProbe.functionName) function with message \"ok\"."
                )
            ],
            toolChoice: .init(functionName: ToolRegistry.capabilityProbe.functionName),
            tools: [ToolRegistry.capabilityProbe.tool]
        )
        let returnedToolCall = response.choices.contains { choice in
            choice.message.toolCalls?.contains { toolCall in
                toolCall.function.name == ToolRegistry.capabilityProbe.functionName
            } == true
        }

        if !returnedToolCall {
            throw AIServiceError.missingToolCallResult
        }
    }

    private static func performChatCompletion(
        with configuration: AIAPIConfiguration,
        model: String,
        messages: [ChatCompletionsRequest.Message],
        toolChoice: ChatCompletionsRequest.ToolChoice? = nil,
        tools: [ChatCompletionsRequest.Tool]? = nil
    ) async throws -> ChatCompletionResponse {
        let request = try makeRequest(
            url: configuration.url(path: "chat/completions"),
            method: .post,
            apiKey: configuration.apiKey,
            body: ChatCompletionsRequest(
                messages: messages,
                model: model,
                store: false,
                stream: false,
                toolChoice: toolChoice,
                tools: tools
            )
        )

        let data = try await performDataRequest(
            AppAF.session.request(request).validate(statusCode: acceptedStatusCodes)
        )
        return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    }

    private static func performDataRequest(_ request: DataRequest) async throws -> Data {
        let response = await request.serializingData(automaticallyCancelling: true).response
        switch response.result {
        case .success(let data):
            return data
        case .failure(let error):
            throw mapDataRequestError(error, response: response.response, data: response.data)
        }
    }

    private static func makeAPIConfiguration(baseURL: String, apiKey: String) throws -> AIAPIConfiguration {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedBaseURL),
              let scheme = components.scheme,
              let host = components.host,
              !host.isEmpty,
              ["http", "https"].contains(scheme),
              components.query == nil,
              components.fragment == nil
        else {
            throw AIServiceError.invalidBaseURL
        }

        let normalizedPath = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = normalizedPath.isEmpty ? "" : "/\(normalizedPath)"

        guard let url = components.url else {
            throw AIServiceError.invalidBaseURL
        }

        return AIAPIConfiguration(
            baseURL: url,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func makeRequest(
        url: URL,
        method: HTTPMethod,
        apiKey: String
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.method = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func makeRequest<Body: Encodable>(
        url: URL,
        method: HTTPMethod,
        apiKey: String,
        body: Body
    ) throws -> URLRequest {
        var request = try makeRequest(url: url, method: method, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private static func makeStreamRequest<Body: Encodable>(
        url: URL,
        method: HTTPMethod,
        apiKey: String,
        body: Body
    ) throws -> URLRequest {
        var request = try makeRequest(url: url, method: method, apiKey: apiKey, body: body)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }

    private static func mapDataRequestError(
        _ error: AFError,
        response: HTTPURLResponse?,
        data: Data?
    ) -> Error {
        if let message = extractAPIErrorMessage(from: data) {
            return AIServiceError.requestFailed(message)
        }

        if let response {
            return AIServiceError.requestFailed("HTTP \(response.statusCode)")
        }

        return unwrapTransportError(error)
    }

    private static func mapStreamError(_ error: AFError, response: HTTPURLResponse?) -> Error {
        if let response {
            return AIServiceError.requestFailed("HTTP \(response.statusCode)")
        }

        return unwrapTransportError(error)
    }

    private static func unwrapTransportError(_ error: AFError) -> Error {
        if case .sessionTaskFailed(let underlyingError) = error {
            return underlyingError
        }

        return error
    }

    private static func extractAPIErrorMessage(from data: Data?) -> String? {
        guard let data, !data.isEmpty else {
            return nil
        }

        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            if let message = envelope.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return message
            }
            if let message = envelope.message?.trimmingCharacters(in: .whitespacesAndNewlines),
               !message.isEmpty {
                return message
            }
        }

        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           text.first != "{",
           text.first != "[" {
            return text
        }

        return nil
    }

    private static func decodeResponsesOutputText(from data: Data) throws -> String? {
        let response = try JSONDecoder().decode(ResponsesResponse.self, from: data)
        return response.resolvedText
    }

    fileprivate static func append(_ delta: String, to current: inout String) -> String? {
        guard !delta.isEmpty else {
            return nil
        }

        current += delta
        return current
    }

    private static func replace(with text: String, current: inout String) -> String? {
        guard text != current else {
            return nil
        }

        current = text
        return current
    }

    private static func resolveAssistantMessageText(_ message: ChatCompletionResponse.Message) throws -> String {
        if let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
           !content.isEmpty {
            return content
        }

        if let refusal = message.refusal?.trimmingCharacters(in: .whitespacesAndNewlines),
           !refusal.isEmpty {
            return refusal
        }

        throw AIServiceError.requestFailed("模型没有返回可用的消息内容")
    }
}

private extension AIService.ConversationMessage {
    var sanitized: Self? {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return nil
        }

        return Self(role: role, content: trimmedContent)
    }

    var responsesInputMessage: ResponsesCreateRequest.InputMessage {
        .init(role: responsesRole, content: content)
    }

    var chatCompletionMessage: ChatCompletionsRequest.Message {
        .init(role: chatRole, content: content)
    }

    private var responsesRole: String {
        switch role {
        case .system:
            return "system"
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        }
    }

    private var chatRole: String {
        responsesRole
    }
}

private struct AIAPIConfiguration {
    let baseURL: URL
    let apiKey: String

    func url(path: String) -> URL {
        path
            .split(separator: "/")
            .reduce(baseURL) { partialURL, component in
                partialURL.appendingPathComponent(String(component))
            }
    }
}

private struct ModelsResponse: Decodable {
    let data: [AIService.AIModelInfo]
}

private struct ResponsesCreateRequest: Encodable {
    let input: [InputMessage]
    let model: String
    let store: Bool?
    let stream: Bool?

    struct InputMessage: Encodable {
        let role: String
        let content: String
        let type: String = "message"
    }
}

struct ChatCompletionsRequest: Encodable {
    let messages: [Message]
    let model: String
    let store: Bool?
    let stream: Bool?
    let toolChoice: ToolChoice?
    let tools: [Tool]?

    struct Message: Encodable {
        let role: String
        let content: String?
        let toolCalls: [AssistantToolCall]?
        let toolCallID: String?

        init(
            role: String,
            content: String? = nil,
            toolCalls: [AssistantToolCall]? = nil,
            toolCallID: String? = nil
        ) {
            self.role = role
            self.content = content
            self.toolCalls = toolCalls
            self.toolCallID = toolCallID
        }

        static func toolResponse(toolCallID: String, content: String) -> Self {
            .init(role: "tool", content: content, toolCallID: toolCallID)
        }

        struct AssistantToolCall: Encodable {
            let id: String
            let type: String = "function"
            let function: FunctionCall

            struct FunctionCall: Encodable {
                let name: String
                let arguments: String
            }
        }

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
            case toolCallID = "tool_call_id"
        }
    }

    struct ToolChoice: Encodable {
        let type: String = "function"
        let function: FunctionReference

        init(functionName: String) {
            self.function = .init(name: functionName)
        }

        struct FunctionReference: Encodable {
            let name: String
        }
    }

    struct Tool: Encodable {
        let type: String = "function"
        let function: FunctionDefinition

        struct FunctionDefinition: Encodable {
            let name: String
            let description: String?
            let parameters: FunctionParametersSchema?
            let strict: Bool?
        }
    }

    enum CodingKeys: String, CodingKey {
        case messages
        case model
        case store
        case stream
        case toolChoice = "tool_choice"
        case tools
    }
}

struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
        let refusal: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case content
            case refusal
            case toolCalls = "tool_calls"
        }
    }

    struct ToolCall: Decodable {
        let id: String
        let function: FunctionCall

        var requestToolCall: ChatCompletionsRequest.Message.AssistantToolCall {
            .init(
                id: id,
                function: .init(
                    name: function.name,
                    arguments: function.arguments
                )
            )
        }
    }

    struct FunctionCall: Decodable {
        let name: String
        let arguments: String
    }
}

private struct StreamingToolRoundState {
    private var previewAccumulator = AIService.ReasoningTaggedTextAccumulator()
    private(set) var assistantContent = ""
    private(set) var assistantRefusal = ""
    private var toolCalls = StreamingToolCallAccumulator()

    var previewText: String {
        previewAccumulator.text
    }

    var hasToolCalls: Bool {
        toolCalls.hasToolCalls
    }

    var assistantMessageContent: String? {
        assistantContent.isEmpty ? nil : assistantContent
    }

    var hasResolvedAssistantMessage: Bool {
        !assistantContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !assistantRefusal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @discardableResult
    mutating func apply(_ chunk: ChatCompletionStreamChunk) throws -> Bool {
        var updatedPreview = false

        for choice in chunk.choices {
            guard let delta = choice.delta else { continue }

            if let reasoning = delta.reasoningTextDelta,
               previewAccumulator.appendReasoning(reasoning) != nil {
                updatedPreview = true
            }

            if let content = delta.content {
                assistantContent += content
                if previewAccumulator.appendVisibleText(content) != nil {
                    updatedPreview = true
                }
            }

            if let refusal = delta.refusal {
                assistantRefusal += refusal
                if previewAccumulator.appendVisibleText(refusal) != nil {
                    updatedPreview = true
                }
            }

            if let toolCallDeltas = delta.toolCalls, !toolCallDeltas.isEmpty {
                try toolCalls.apply(toolCallDeltas)
            }
        }

        return updatedPreview
    }

    @discardableResult
    mutating func finalizePreviewIfNeeded() -> Bool {
        previewAccumulator.finalizeReasoningIfNeeded() != nil
    }

    func finalizedToolCalls() throws -> [ChatCompletionResponse.ToolCall] {
        try toolCalls.finalizedToolCalls()
    }
}

private struct StreamingToolCallAccumulator {
    private var builders: [Int: PartialToolCall] = [:]
    private var orderedIndices: [Int] = []

    var hasToolCalls: Bool {
        !orderedIndices.isEmpty
    }

    mutating func apply(_ deltas: [ChatCompletionStreamChunk.Delta.ToolCallDelta]) throws {
        for delta in deltas {
            if let type = delta.type?.trimmingCharacters(in: .whitespacesAndNewlines),
               !type.isEmpty,
               type != "function" {
                throw AIServiceError.requestFailed("暂不支持 \(type) 类型的工具调用")
            }

            let index = try resolvedIndex(for: delta)
            if builders[index] == nil {
                builders[index] = PartialToolCall()
                orderedIndices.append(index)
            }
            builders[index]?.merge(delta)
        }
    }

    func finalizedToolCalls() throws -> [ChatCompletionResponse.ToolCall] {
        try orderedIndices.sorted().map { index in
            guard let builder = builders[index] else {
                throw AIServiceError.invalidStreamPayload
            }
            return try builder.finalized(index: index)
        }
    }

    private func resolvedIndex(
        for delta: ChatCompletionStreamChunk.Delta.ToolCallDelta
    ) throws -> Int {
        if let index = delta.index {
            return index
        }

        if orderedIndices.count == 1, let existingIndex = orderedIndices.first {
            return existingIndex
        }

        if let lastIndex = orderedIndices.last,
           delta.id == nil,
           delta.function?.name == nil {
            return lastIndex
        }

        if orderedIndices.isEmpty {
            return 0
        }

        throw AIServiceError.invalidStreamPayload
    }

    private struct PartialToolCall {
        var id: String?
        var name: String?
        var arguments = ""

        mutating func merge(_ delta: ChatCompletionStreamChunk.Delta.ToolCallDelta) {
            if let id = delta.id, !id.isEmpty {
                self.id = id
            }

            if let name = delta.function?.name, !name.isEmpty {
                self.name = name
            }

            if let arguments = delta.function?.arguments, !arguments.isEmpty {
                self.arguments += arguments
            }
        }

        func finalized(index: Int) throws -> ChatCompletionResponse.ToolCall {
            guard let id, !id.isEmpty,
                  let name, !name.isEmpty,
                  !arguments.isEmpty else {
                throw AIServiceError.requestFailed("第 \(index + 1) 个工具调用的流式参数不完整")
            }

            return .init(
                id: id,
                function: .init(
                    name: name,
                    arguments: arguments
                )
            )
        }
    }
}

private struct ChatCompletionStreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let index: Int?
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
        let refusal: String?
        let reasoningContent: String?
        let reasoning: String?
        let toolCalls: [ToolCallDelta]?

        struct ToolCallDelta: Decodable {
            let index: Int?
            let id: String?
            let type: String?
            let function: FunctionCallDelta?
        }

        struct FunctionCallDelta: Decodable {
            let name: String?
            let arguments: String?
        }

        var reasoningTextDelta: String? {
            if let reasoningContent, !reasoningContent.isEmpty {
                return reasoningContent
            }
            if let reasoning, !reasoning.isEmpty {
                return reasoning
            }
            return nil
        }

        enum CodingKeys: String, CodingKey {
            case content
            case refusal
            case reasoningContent = "reasoning_content"
            case reasoning
            case toolCalls = "tool_calls"
        }
    }
}

private struct ResponsesStreamEvent: Decodable {
    let type: String
    let delta: String?
    let text: String?
    let refusal: String?
    let error: APIErrorEnvelope.APIErrorBody?
    let response: FailedResponse?

    struct FailedResponse: Decodable {
        let error: APIErrorEnvelope.APIErrorBody?
        let statusDetails: StatusDetails?

        struct StatusDetails: Decodable {
            let error: APIErrorEnvelope.APIErrorBody?

            enum CodingKeys: String, CodingKey {
                case error
            }
        }

        enum CodingKeys: String, CodingKey {
            case error
            case statusDetails = "status_details"
        }
    }

    var errorMessage: String? {
        if let message = error?.message, !message.isEmpty {
            return message
        }
        if let message = response?.error?.message, !message.isEmpty {
            return message
        }
        if let message = response?.statusDetails?.error?.message, !message.isEmpty {
            return message
        }
        return nil
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorBody?
    let message: String?

    struct APIErrorBody: Decodable {
        let message: String?
    }
}

private struct ResponsesResponse: Decodable {
    let outputText: String?
    let output: [OutputItem]?

    var resolvedText: String? {
        if let outputText = outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outputText.isEmpty {
            return outputText
        }

        let messageText = output?
            .filter { $0.type == "message" && ($0.role == nil || $0.role == "assistant") }
            .compactMap(\.resolvedText)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let messageText, !messageText.isEmpty {
            return messageText
        }

        return nil
    }

    struct OutputItem: Decodable {
        let type: String
        let role: String?
        let content: [ContentPart]?

        var resolvedText: String? {
            let text = content?
                .compactMap(\.resolvedText)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let text, !text.isEmpty {
                return text
            }

            return nil
        }
    }

    struct ContentPart: Decodable {
        let type: String
        let text: String?
        let refusal: String?

        var resolvedText: String? {
            switch type {
            case "output_text":
                return text
            case "refusal":
                return refusal
            default:
                return nil
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

struct SSEEventParser {
    static let donePayload = Data("[DONE]".utf8)

    private static let dataPrefix = Array("data:".utf8)
    private static let lineFeed: UInt8 = 10
    private static let carriageReturn: UInt8 = 13
    private static let space: UInt8 = 32
    private static let tab: UInt8 = 9
    private static let openBrace: UInt8 = 123
    private static let closeBrace: UInt8 = 125
    private static let openBracket: UInt8 = 91
    private static let closeBracket: UInt8 = 93
    private static let quote: UInt8 = 34
    private static let backslash: UInt8 = 92

    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        return try extractEvents(final: false)
    }

    mutating func finish() throws -> [Data] {
        try extractEvents(final: true)
    }

    private mutating func extractEvents(final: Bool) throws -> [Data] {
        var payloads: [Data] = []

        while true {
            trimLeadingIgnorableBytes()

            if let separatorRange = standardSeparatorRange() {
                let eventBytes = Data(buffer.prefix(separatorRange.lowerBound))
                buffer.removeSubrange(0..<separatorRange.upperBound)
                if let payload = try decodeStandardEvent(from: eventBytes) {
                    payloads.append(payload)
                }
                continue
            }

            switch try extractFallbackEvent(final: final) {
            case .event(let payload):
                payloads.append(payload)
                continue
            case .none:
                break
            }

            break
        }

        if final {
            trimLeadingIgnorableBytes()
            if !buffer.isEmpty {
                if let payload = try decodeStandardEvent(from: buffer) {
                    payloads.append(payload)
                    buffer.removeAll(keepingCapacity: true)
                } else {
                    throw AIServiceError.invalidStreamPayload
                }
            }
        }

        return payloads
    }

    private mutating func trimLeadingIgnorableBytes() {
        while let first = buffer.first,
              first == Self.lineFeed || first == Self.carriageReturn
                || first == Self.space || first == Self.tab {
            buffer.removeFirst()
        }
    }

    private func standardSeparatorRange() -> Range<Int>? {
        guard buffer.count >= 2 else {
            return nil
        }

        for index in 0..<(buffer.count - 1) {
            if buffer[index] == Self.lineFeed && buffer[index + 1] == Self.lineFeed {
                return index..<(index + 2)
            }

            if index + 3 < buffer.count,
               buffer[index] == Self.carriageReturn,
               buffer[index + 1] == Self.lineFeed,
               buffer[index + 2] == Self.carriageReturn,
               buffer[index + 3] == Self.lineFeed {
                return index..<(index + 4)
            }
        }

        return nil
    }

    private func decodeStandardEvent(from data: Data) throws -> Data? {
        guard !data.isEmpty else {
            return nil
        }

        let normalized = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var dataLines: [Substring] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") {
                continue
            }

            guard line.hasPrefix("data:") else {
                continue
            }

            var payload = line.dropFirst(5)
            if payload.first == " " {
                payload = payload.dropFirst()
            }
            dataLines.append(payload)
        }

        guard !dataLines.isEmpty else {
            return nil
        }

        return Data(dataLines.joined(separator: "\n").utf8)
    }

    private mutating func extractFallbackEvent(final: Bool) throws -> ExtractionResult {
        switch try extractRawJSONEvent(final: final) {
        case .event(let payload):
            return .event(payload)
        case .none:
            break
        }

        // OpenAI-style SSE uses newline-delimited `data:` frames, but some compatible providers
        // concatenate `data:` payloads without any `\n`, so we must recover events without
        // relying on line breaks alone.
        guard buffer.starts(with: Self.dataPrefix) else {
            return .none
        }

        var payloadStart = Self.dataPrefix.count
        while payloadStart < buffer.count,
              buffer[payloadStart] == Self.space || buffer[payloadStart] == Self.tab {
            payloadStart += 1
        }

        guard payloadStart < buffer.count else {
            if final {
                throw AIServiceError.invalidStreamPayload
            }
            return .none
        }

        let payloadBytes = buffer[payloadStart...]
        if payloadBytes.starts(with: Self.donePayload) {
            let payloadEnd = payloadStart + Self.donePayload.count
            buffer.removeSubrange(0..<payloadEnd)
            return .event(Self.donePayload)
        }

        guard let payloadEnd = balancedJSONPayloadEnd(startingAt: payloadStart) else {
            if final {
                throw AIServiceError.invalidStreamPayload
            }
            return .none
        }

        let payload = Data(buffer[payloadStart..<payloadEnd])
        buffer.removeSubrange(0..<payloadEnd)
        return .event(payload)
    }

    private mutating func extractRawJSONEvent(final: Bool) throws -> ExtractionResult {
        guard let payloadStart = firstMeaningfulByteIndex() else {
            return .none
        }

        let opening = buffer[payloadStart]
        guard opening == Self.openBrace || opening == Self.openBracket else {
            return .none
        }

        guard let payloadEnd = balancedJSONPayloadEnd(startingAt: payloadStart) else {
            if final {
                throw AIServiceError.invalidStreamPayload
            }
            return .none
        }

        let payload = Data(buffer[payloadStart..<payloadEnd])
        buffer.removeSubrange(0..<payloadEnd)
        return .event(payload)
    }

    private func firstMeaningfulByteIndex() -> Int? {
        for index in buffer.indices {
            let byte = buffer[index]
            if byte == Self.lineFeed || byte == Self.carriageReturn
                || byte == Self.space || byte == Self.tab {
                continue
            }
            return index
        }

        return nil
    }

    private func balancedJSONPayloadEnd(startingAt start: Int) -> Int? {
        guard start < buffer.count else {
            return nil
        }

        let opening = buffer[start]
        let closing: UInt8
        switch opening {
        case Self.openBrace:
            closing = Self.closeBrace
        case Self.openBracket:
            closing = Self.closeBracket
        default:
            return nil
        }

        var depth = 0
        var index = start
        var isInsideString = false
        var isEscaping = false

        while index < buffer.count {
            let byte = buffer[index]

            if isInsideString {
                if isEscaping {
                    isEscaping = false
                } else if byte == Self.backslash {
                    isEscaping = true
                } else if byte == Self.quote {
                    isInsideString = false
                }
            } else {
                if byte == Self.quote {
                    isInsideString = true
                } else if byte == opening {
                    depth += 1
                } else if byte == closing {
                    depth -= 1
                    if depth == 0 {
                        return index + 1
                    }
                }
            }

            index += 1
        }

        return nil
    }

    private enum ExtractionResult {
        case none
        case event(Data)
    }
}
