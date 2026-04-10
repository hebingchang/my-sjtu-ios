//
//  CanvasTodoTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class CanvasTodoItemsToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_canvas_todo_items",
                displayName: "获取 Canvas 待办事项",
                category: .query,
                functionDescription: "获取当前 jAccount 账户下 Canvas 的近期待办事项列表，包括需要提交的作业等。调用前会检查该 jAccount 是否已启用 Canvas 功能；若未启用，则返回提示用户前往账户页授权打开。",
                parametersSchema: .emptyObject,
                isAvailableInChat: true
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            switch AIService.canvasAuthorizationState() {
            case .notEnabled:
                return AIService.encodeToolExecutionError(
                    .init(error: "当前 jAccount 尚未打开 Canvas 功能，请先在账户页中授权打开。")
                )
            case .missingToken:
                return AIService.encodeToolExecutionError(
                    .init(error: "Canvas 令牌不可用，请在账户页中重新启用 Canvas 功能。")
                )
            case .ready(let token):
                do {
                    let items = try await AIService.fetchCanvasTodoItems(token: token)
                    return AIService.encodeToolExecutionResult(
                        CanvasTodoItemsToolResult(
                            itemCount: items.count,
                            items: items
                        )
                    )
                } catch {
                    return AIService.encodeToolExecutionError(
                        .init(error: AIService.canvasTodoErrorText(error))
                    )
                }
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            .init(
                text: "已调用“获取 Canvas 待办事项”",
                functionName: functionName,
                category: category,
                invocationKey: functionName
            )
        }
    }
}
