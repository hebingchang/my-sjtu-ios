//
//  CampusCardTransactionsTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class CampusCardTransactionsToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_campus_card_transactions",
                displayName: "查询校园卡交易记录",
                category: .query,
                functionDescription: "查询当前 jAccount 账户下指定校园卡在一段时间内的交易记录，返回校园卡交易和思源码消费记录的合并时间线。调用前会检查该 jAccount 是否已启用校园卡功能；若未启用，则直接返回提示用户前往账户页启用校园卡功能。",
                parametersSchema: .campusCardDateRange,
                isAvailableInChat: true
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            guard let account = AIService.enabledCampusCardAccount() else {
                return AIService.encodeToolExecutionError(
                    .init(error: AIService.campusCardUnavailableErrorText())
                )
            }

            let arguments: CampusCardDateRangeToolArguments
            do {
                arguments = try JSONDecoder().decode(
                    CampusCardDateRangeToolArguments.self,
                    from: Data(argumentsJSON.utf8)
                )
            } catch {
                return AIService.encodeToolExecutionError(
                    .init(error: "工具参数解析失败：\(error.localizedDescription)")
                )
            }

            let cardNo = arguments.cardNo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cardNo.isEmpty else {
                return AIService.encodeToolExecutionError(
                    .init(error: "card_no 参数不能为空。")
                )
            }

            let dateRange: (startDate: Date, endDate: Date)
            do {
                dateRange = try AIService.parseCampusCardToolDateRange(
                    startDate: arguments.startDate,
                    endDate: arguments.endDate
                )
            } catch {
                return AIService.encodeToolExecutionError(
                    .init(error: AIService.campusCardDateRangeErrorText(error))
                )
            }

            do {
                let result = try await AIService.fetchCampusCardTransactionsResult(
                    account: account,
                    cardNo: cardNo,
                    startDate: dateRange.startDate,
                    endDate: dateRange.endDate
                )
                return AIService.encodeToolExecutionResult(result)
            } catch {
                return AIService.encodeToolExecutionError(
                    .init(error: AIService.campusCardToolErrorText(error))
                )
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            guard let parsed = parsedInvocation(argumentsJSON: argumentsJSON) else {
                return await super.invocationStatusPayload(argumentsJSON: argumentsJSON)
            }

            return .init(
                text: "已调用“查询\(maskedCardNoText(parsed.cardNo))\(AIService.formattedToolStatusDate(parsed.startDate))至\(AIService.formattedToolStatusDate(parsed.endDate))的交易记录”",
                functionName: functionName,
                category: category,
                invocationKey: "\(functionName)|card_no=\(parsed.cardNo)|start_date=\(parsed.startDate.formattedDate())|end_date=\(parsed.endDate.formattedDate())"
            )
        }

        private func parsedInvocation(
            argumentsJSON: String
        ) -> (cardNo: String, startDate: Date, endDate: Date)? {
            guard let arguments = try? JSONDecoder().decode(
                CampusCardDateRangeToolArguments.self,
                from: Data(argumentsJSON.utf8)
            ) else {
                return nil
            }

            let cardNo = arguments.cardNo.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cardNo.isEmpty,
                  let dateRange = try? AIService.parseCampusCardToolDateRange(
                      startDate: arguments.startDate,
                      endDate: arguments.endDate
                  ) else {
                return nil
            }

            return (cardNo, dateRange.startDate, dateRange.endDate)
        }

        private func maskedCardNoText(_ cardNo: String) -> String {
            if cardNo.count <= 4 {
                return "校园卡 \(cardNo) "
            }

            return "尾号 \(cardNo.suffix(4)) 的校园卡 "
        }
    }
}
