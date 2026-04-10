//
//  CampusCardInformationTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class CampusCardInformationToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_campus_card_information",
                displayName: "获取校园卡信息",
                category: .query,
                functionDescription: "获取当前 jAccount 用户名下的校园卡信息，包括 jAccount 用户名、姓名、学号、卡号、卡类型、余额和卡状态。调用前会检查该 jAccount 是否已启用校园卡功能；若未启用，则直接返回提示用户前往账户页启用校园卡功能。",
                parametersSchema: .emptyObject,
                isAvailableInChat: true
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            guard let account = AIService.enabledCampusCardAccount() else {
                return AIService.encodeToolExecutionError(
                    .init(error: AIService.campusCardUnavailableErrorText())
                )
            }

            do {
                let result = try await AIService.fetchCampusCardInformationResult(account: account)
                return AIService.encodeToolExecutionResult(result)
            } catch {
                return AIService.encodeToolExecutionError(
                    .init(error: AIService.campusCardToolErrorText(error))
                )
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            .init(
                text: "已调用“获取校园卡信息”",
                functionName: functionName,
                category: category,
                invocationKey: functionName
            )
        }
    }
}
