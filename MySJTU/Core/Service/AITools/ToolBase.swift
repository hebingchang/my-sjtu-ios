//
//  ToolBase.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    class ToolDefinition: @unchecked Sendable {
        let functionName: String
        let displayName: String
        let category: AIToolCallCategory
        let functionDescription: String
        let parametersSchema: FunctionParametersSchema?
        let isAvailableInChat: Bool
        let requiresUserAuthorization: Bool

        init(
            functionName: String,
            displayName: String,
            category: AIToolCallCategory,
            functionDescription: String,
            parametersSchema: FunctionParametersSchema?,
            isAvailableInChat: Bool,
            requiresUserAuthorization: Bool = true
        ) {
            self.functionName = functionName
            self.displayName = displayName
            self.category = category
            self.functionDescription = functionDescription
            self.parametersSchema = parametersSchema
            self.isAvailableInChat = isAvailableInChat
            self.requiresUserAuthorization = requiresUserAuthorization
        }

        var tool: ChatCompletionsRequest.Tool {
            .init(
                function: .init(
                    name: functionName,
                    description: functionDescription,
                    parameters: parametersSchema,
                    strict: parametersSchema?.supportsStrictMode == true ? true : nil
                )
            )
        }

        func execute(argumentsJSON: String) async -> String {
            AIService.encodeToolExecutionError(
                .init(error: "工具“\(displayName)”尚未实现执行逻辑。")
            )
        }

        func execute(
            argumentsJSON: String,
            toolNavigationHandler: ToolNavigationHandler?
        ) async -> String {
            await execute(argumentsJSON: argumentsJSON)
        }

        func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            .init(
                text: "已调用“\(displayName)”",
                functionName: functionName,
                category: category,
                invocationKey: AIService.genericToolInvocationKey(
                    functionName: functionName,
                    argumentsJSON: argumentsJSON
                )
            )
        }
    }
}
