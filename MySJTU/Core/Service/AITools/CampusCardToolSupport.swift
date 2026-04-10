//
//  CampusCardToolSupport.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

private let campusCardLicenseRegex = /(([京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼使领][A-Z](([0-9]{5}[DF])|([DF]([A-HJ-NP-Z0-9])[0-9]{4})))|([京津沪渝冀豫云辽黑湘皖鲁新苏浙赣鄂桂甘晋蒙陕吉闽贵粤青藏川宁琼使领][A-Z][A-HJ-NP-Z0-9]{4}[A-HJ-NP-Z0-9挂学警港澳使领]))/

private enum CampusCardToolDateRangeError: Error {
    case invalidStartDate
    case invalidEndDate
    case endBeforeStart
}

private enum CampusCardMergedTransactionSource: String {
    case campusCard = "校园卡"
    case unicode = "思源码"
}

private enum CampusCardCostType: String, CaseIterable {
    case restaurant = "餐饮"
    case shopping = "购物"
    case bathroom = "浴室"
    case charging = "充电"
    case entertainment = "文娱体育"
    case transportation = "交通"
    case other = "其他"
}

private struct CampusCardMergedTransaction {
    let source: CampusCardMergedTransactionSource
    let dateTime: Int
    let system: String
    let merchantNo: String?
    let merchant: String
    let description: String
    let amount: Double
    let cardBalance: Double?

    var occurredAt: Date {
        Date(timeIntervalSince1970: Double(dateTime) / 1000)
    }
}

private struct CampusCardToolContext {
    let account: WebAuthAccount
    let profile: Profile
    let cards: [CampusCard]

    var unicodeEnabled: Bool {
        account.enabledFeatures.contains(.unicode)
    }
}

private struct CampusCardMergedTransactionSnapshot {
    let cardNo: String
    let startDate: Date
    let endDate: Date
    let unicodeIncluded: Bool
    let warnings: [String]
    let cardTransactions: [CampusCardMergedTransaction]
    let unicodeTransactions: [CampusCardMergedTransaction]
    let mergedTransactions: [CampusCardMergedTransaction]
}

extension AIService {
    static func enabledCampusCardAccount(
        userDefaults: UserDefaults = .standard
    ) -> WebAuthAccount? {
        storedAccounts(userDefaults: userDefaults).first {
            $0.provider == .jaccount && $0.enabledFeatures.contains(.campusCard)
        }
    }

    static func parseCampusCardToolDateRange(
        startDate: String,
        endDate: String
    ) throws -> (startDate: Date, endDate: Date) {
        guard let parsedStartDate = parseToolDate(startDate) else {
            throw CampusCardToolDateRangeError.invalidStartDate
        }

        guard let parsedEndDate = parseToolDate(endDate) else {
            throw CampusCardToolDateRangeError.invalidEndDate
        }

        let normalizedStartDate = parsedStartDate.startOfDay()
        let normalizedEndDate = parsedEndDate.startOfDay().addDays(1).addSeconds(-1)

        guard normalizedEndDate >= normalizedStartDate else {
            throw CampusCardToolDateRangeError.endBeforeStart
        }

        return (normalizedStartDate, normalizedEndDate)
    }

    static func campusCardDateRangeErrorText(_ error: Error) -> String {
        guard let error = error as? CampusCardToolDateRangeError else {
            return "日期范围无效。"
        }

        switch error {
        case .invalidStartDate:
            return "start_date 参数无效，必须是 YYYY-MM-DD 或 ISO-8601 日期。"
        case .invalidEndDate:
            return "end_date 参数无效，必须是 YYYY-MM-DD 或 ISO-8601 日期。"
        case .endBeforeStart:
            return "end_date 不能早于 start_date。"
        }
    }

    static func campusCardUnavailableErrorText() -> String {
        "当前 jAccount 尚未启用校园卡功能，请先在账户页中启用校园卡功能。"
    }

    static func unicodeExcludedWarningText() -> String {
        "当前 jAccount 未启用思源码功能，结果不包含思源码消费记录。"
    }

    static func campusCardToolErrorText(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .sessionExpired:
                return "jAccount 会话可能已过期，请在账户页中重新登录后再试。"
            case .noAccount:
                return "当前未找到可用的 jAccount 账户，请先登录并启用校园卡功能。"
            case .remoteError(let message), .runtimeError(let message):
                return message
            case .internalError:
                return "无法获取校园卡信息，请稍后重试。"
            }
        }

        if let authError = error as? WebAuthError {
            switch authError {
            case .tokenWithScopeNotFound:
                return "校园卡令牌不可用，请在账户页中重新启用校园卡功能。"
            case .tokenExpired:
                return "校园卡令牌已过期，请在账户页中重新启用校园卡功能。"
            default:
                break
            }
        }

        return "无法获取校园卡信息，请稍后重试。"
    }

    static func unicodeToolErrorText(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .sessionExpired:
                return "jAccount 会话可能已过期，请在账户页中重新登录后再试。"
            case .noAccount:
                return "当前未找到可用的 jAccount 账户，请先登录并启用思源码功能。"
            case .remoteError(let message), .runtimeError(let message):
                return message
            case .internalError:
                return "无法获取思源码消费记录，请稍后重试。"
            }
        }

        if let authError = error as? WebAuthError {
            switch authError {
            case .tokenWithScopeNotFound:
                return "思源码令牌不可用，请在账户页中重新启用思源码功能。"
            case .tokenExpired:
                return "思源码令牌已过期，请在账户页中重新启用思源码功能。"
            default:
                break
            }
        }

        return "无法获取思源码消费记录，请稍后重试。"
    }

    static func fetchCampusCardInformationResult(
        account: WebAuthAccount
    ) async throws -> CampusCardInformationToolResult {
        let context = try await fetchCampusCardToolContext(account: account)

        return CampusCardInformationToolResult(
            jAccountAccount: context.profile.account,
            userName: context.profile.name,
            userCode: context.profile.code,
            cardCount: context.cards.count,
            cards: context.cards.map { card in
                CampusCardInformationToolResult.Card(
                    cardNo: card.cardNo,
                    cardId: card.cardId,
                    bankNo: card.bankNo,
                    expireDate: card.expireDate,
                    cardType: campusCardTypeText(card.cardType),
                    cardBalance: card.cardBalance,
                    transBalance: card.transBalance,
                    lost: card.lost,
                    frozen: card.frozen,
                    organizationName: card.user.organize?.name
                )
            }
        )
    }

    static func fetchCampusCardTransactionsResult(
        account: WebAuthAccount,
        cardNo: String,
        startDate: Date,
        endDate: Date
    ) async throws -> CampusCardTransactionsToolResult {
        let snapshot = try await fetchCampusCardMergedTransactionSnapshot(
            account: account,
            cardNo: cardNo,
            startDate: startDate,
            endDate: endDate
        )

        let expenseTransactions = snapshot.mergedTransactions.filter { $0.amount < 0 }
        let incomeTransactions = snapshot.mergedTransactions.filter { $0.amount > 0 }

        return CampusCardTransactionsToolResult(
            cardNo: snapshot.cardNo,
            startDate: snapshot.startDate.formattedDate(),
            endDate: snapshot.endDate.formattedDate(),
            unicodeIncluded: snapshot.unicodeIncluded,
            warnings: snapshot.warnings.isEmpty ? nil : snapshot.warnings,
            itemCount: snapshot.mergedTransactions.count,
            expenseCount: expenseTransactions.count,
            expenseAmount: expenseTransactions.reduce(0) { $0 + (-$1.amount) },
            incomeCount: incomeTransactions.count,
            incomeAmount: incomeTransactions.reduce(0) { $0 + $1.amount },
            items: snapshot.mergedTransactions.map { transaction in
                CampusCardTransactionsToolResult.Item(
                    source: transaction.source.rawValue,
                    transactionAt: transaction.occurredAt.formatted(format: "yyyy-MM-dd HH:mm:ss"),
                    dateTimeMs: transaction.dateTime,
                    system: transaction.system,
                    merchantNo: transaction.merchantNo,
                    merchant: transaction.merchant,
                    description: transaction.description,
                    amount: transaction.amount,
                    cardBalance: transaction.cardBalance
                )
            }
        )
    }

    static func fetchCampusCardCostAnalyticsResult(
        account: WebAuthAccount,
        cardNo: String,
        startDate: Date,
        endDate: Date
    ) async throws -> CampusCardCostAnalyticsToolResult {
        let snapshot = try await fetchCampusCardMergedTransactionSnapshot(
            account: account,
            cardNo: cardNo,
            startDate: startDate,
            endDate: endDate
        )

        let expenseTransactions = snapshot.mergedTransactions.filter { $0.amount < 0 }
        let campusCardExpenseTransactions = snapshot.cardTransactions.filter { $0.amount < 0 }
        let unicodeExpenseTransactions = snapshot.unicodeTransactions.filter { $0.amount < 0 }

        return CampusCardCostAnalyticsToolResult(
            cardNo: snapshot.cardNo,
            startDate: snapshot.startDate.formattedDate(),
            endDate: snapshot.endDate.formattedDate(),
            unicodeIncluded: snapshot.unicodeIncluded,
            warnings: snapshot.warnings.isEmpty ? nil : snapshot.warnings,
            expenseTransactionCount: expenseTransactions.count,
            totalExpenseAmount: expenseAmount(of: expenseTransactions),
            campusCardExpenseAmount: expenseAmount(of: campusCardExpenseTransactions),
            unicodeExpenseAmount: snapshot.unicodeIncluded ? expenseAmount(of: unicodeExpenseTransactions) : nil,
            dailyCosts: makeCampusCardDailyCosts(
                transactions: expenseTransactions,
                startDate: snapshot.startDate,
                endDate: snapshot.endDate
            ),
            monthlyCosts: makeCampusCardMonthlyCosts(
                transactions: expenseTransactions,
                startDate: snapshot.startDate,
                endDate: snapshot.endDate
            ),
            categoryCosts: makeCampusCardCategoryCosts(transactions: expenseTransactions),
            hourlyCosts: makeCampusCardHourlyCosts(transactions: expenseTransactions),
            topMerchantsByCount: makeCampusCardTopMerchantsByCount(transactions: expenseTransactions)
        )
    }

    private static func fetchCampusCardToolContext(
        account: WebAuthAccount
    ) async throws -> CampusCardToolContext {
        let api = SJTUOpenAPI(tokens: account.tokens)
        async let profileTask = api.getProfile()
        async let cardsTask = api.getCampusCards()

        let profile = try await profileTask
        let cards = try await cardsTask

        return CampusCardToolContext(
            account: account,
            profile: profile,
            cards: addCampusCardTypes(cards: cards, profile: profile)
        )
    }

    private static func fetchCampusCardMergedTransactionSnapshot(
        account: WebAuthAccount,
        cardNo rawCardNo: String,
        startDate: Date,
        endDate: Date
    ) async throws -> CampusCardMergedTransactionSnapshot {
        let cardNo = rawCardNo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cardNo.isEmpty else {
            throw APIError.runtimeError("card_no 参数不能为空。")
        }

        let api = SJTUOpenAPI(tokens: account.tokens)
        let cards = try await api.getCampusCards()

        guard cards.contains(where: { $0.cardNo == cardNo }) else {
            throw APIError.runtimeError("当前 jAccount 账户下不存在卡号为 \(cardNo) 的校园卡。")
        }

        let beginDateMs = Int(startDate.timeIntervalSince1970 * 1000)
        let endDateMs = Int(endDate.timeIntervalSince1970 * 1000)
        let beginDateSeconds = Int(startDate.timeIntervalSince1970)
        let endDateSeconds = Int(endDate.timeIntervalSince1970)

        if account.enabledFeatures.contains(.unicode) {
            async let cardTransactionsTask = api.getCardTransactions(
                cardNo: cardNo,
                beginDate: beginDateMs,
                endDate: endDateMs
            )
            async let unicodeTransactionsTask = api.getUnicodeTransactions(
                beginDate: beginDateSeconds,
                endDate: endDateSeconds
            )

            let (_, cardTransactions) = try await cardTransactionsTask
            let unicodeTransactions: [UnicodeTransaction]
            do {
                unicodeTransactions = try await unicodeTransactionsTask
            } catch {
                throw APIError.runtimeError("无法获取思源码消费记录：\(unicodeToolErrorText(error))")
            }

            let mergedCardTransactions = cardTransactions.map { transaction in
                CampusCardMergedTransaction(
                    source: .campusCard,
                    dateTime: transaction.dateTime,
                    system: transaction.system,
                    merchantNo: transaction.merchantNo,
                    merchant: transaction.merchant,
                    description: transaction.description,
                    amount: transaction.amount,
                    cardBalance: transaction.cardBalance
                )
            }
            let mergedUnicodeTransactions = unicodeTransactions.map { transaction in
                CampusCardMergedTransaction(
                    source: .unicode,
                    dateTime: transaction.orderTime * 1000,
                    system: transaction.channel,
                    merchantNo: transaction.merchantNo,
                    merchant: transaction.merchant,
                    description: "思源码交易",
                    amount: transaction.amount,
                    cardBalance: nil
                )
            }

            let mergedTransactions = (mergedCardTransactions + mergedUnicodeTransactions).sorted {
                if $0.dateTime != $1.dateTime {
                    return $0.dateTime > $1.dateTime
                }
                return $0.source.rawValue.localizedStandardCompare($1.source.rawValue) == .orderedAscending
            }

            return CampusCardMergedTransactionSnapshot(
                cardNo: cardNo,
                startDate: startDate,
                endDate: endDate,
                unicodeIncluded: true,
                warnings: [],
                cardTransactions: mergedCardTransactions,
                unicodeTransactions: mergedUnicodeTransactions,
                mergedTransactions: mergedTransactions
            )
        } else {
            let (_, cardTransactions) = try await api.getCardTransactions(
                cardNo: cardNo,
                beginDate: beginDateMs,
                endDate: endDateMs
            )
            let mergedCardTransactions = cardTransactions.map { transaction in
                CampusCardMergedTransaction(
                    source: .campusCard,
                    dateTime: transaction.dateTime,
                    system: transaction.system,
                    merchantNo: transaction.merchantNo,
                    merchant: transaction.merchant,
                    description: transaction.description,
                    amount: transaction.amount,
                    cardBalance: transaction.cardBalance
                )
            }

            return CampusCardMergedTransactionSnapshot(
                cardNo: cardNo,
                startDate: startDate,
                endDate: endDate,
                unicodeIncluded: false,
                warnings: [unicodeExcludedWarningText()],
                cardTransactions: mergedCardTransactions,
                unicodeTransactions: [],
                mergedTransactions: mergedCardTransactions.sorted { $0.dateTime > $1.dateTime }
            )
        }
    }

    private static func addCampusCardTypes(
        cards: [CampusCard],
        profile: Profile
    ) -> [CampusCard] {
        var cardsWithType = cards

        for index in 0..<cardsWithType.count {
            let card = cardsWithType[index]
            let identities = profile.identities.filter { $0.code == card.user.code }

            if identities.first(where: {
                $0.userType == "faculty" && $0.type != nil &&
                !$0.type!.id.hasPrefix("4") && !$0.type!.id.hasPrefix("6")
            }) != nil {
                cardsWithType[index].cardType = .working
            } else if identities.first(where: { $0.userType == "postphd" }) != nil {
                cardsWithType[index].cardType = .working
            } else if identities.first(where: {
                $0.userType == "student" && $0.type != nil &&
                ($0.type!.id.hasPrefix("10") || $0.type!.id.hasPrefix("11"))
            }) != nil {
                cardsWithType[index].cardType = .undergraduate
            } else if identities.first(where: {
                $0.userType == "student" && $0.type != nil &&
                $0.type!.id.hasPrefix("2") && !$0.type!.id.hasPrefix("23")
            }) != nil {
                cardsWithType[index].cardType = .master
            } else if identities.first(where: {
                $0.userType == "student" && $0.type != nil &&
                $0.type!.id.hasPrefix("3")
            }) != nil {
                cardsWithType[index].cardType = .doctor
            }
        }

        return cardsWithType
    }

    private static func campusCardTypeText(_ cardType: CampusCard.CardType) -> String {
        switch cardType {
        case .general:
            return "校园卡"
        case .working:
            return "教工卡"
        case .undergraduate:
            return "本科生"
        case .master:
            return "硕士生"
        case .doctor:
            return "博士生"
        }
    }

    private static func expenseAmount(
        of transactions: [CampusCardMergedTransaction]
    ) -> Double {
        transactions.reduce(0) { partialResult, transaction in
            partialResult + (transaction.amount < 0 ? -transaction.amount : 0)
        }
    }

    private static func makeCampusCardDailyCosts(
        transactions: [CampusCardMergedTransaction],
        startDate: Date,
        endDate: Date
    ) -> [CampusCardCostAnalyticsToolResult.DailyCost] {
        var dailyCosts: [CampusCardCostAnalyticsToolResult.DailyCost] = []
        var day = startDate.startOfDay()
        let lastDay = endDate.startOfDay()

        while day <= lastDay {
            let nextDay = day.addDays(1)
            let dailyTransactions = transactions.filter { transaction in
                let occurredAt = transaction.occurredAt
                return occurredAt >= day && occurredAt < nextDay
            }

            dailyCosts.append(
                .init(
                    date: day.formattedDate(),
                    expenseAmount: expenseAmount(of: dailyTransactions),
                    transactionCount: dailyTransactions.count
                )
            )

            day = nextDay
        }

        return dailyCosts
    }

    private static func makeCampusCardMonthlyCosts(
        transactions: [CampusCardMergedTransaction],
        startDate: Date,
        endDate: Date
    ) -> [CampusCardCostAnalyticsToolResult.MonthlyCost] {
        var monthlyCosts: [CampusCardCostAnalyticsToolResult.MonthlyCost] = []
        var month = startDate.startOfMonth()
        let lastMonth = endDate.startOfMonth()

        while month <= lastMonth {
            let nextMonth = month.addMonths(1)
            let monthlyTransactions = transactions.filter { transaction in
                let occurredAt = transaction.occurredAt
                return occurredAt >= month && occurredAt < nextMonth
            }

            monthlyCosts.append(
                .init(
                    month: month.formatted(format: "yyyy-MM"),
                    expenseAmount: expenseAmount(of: monthlyTransactions),
                    transactionCount: monthlyTransactions.count
                )
            )

            month = nextMonth
        }

        return monthlyCosts
    }

    private static func makeCampusCardCategoryCosts(
        transactions: [CampusCardMergedTransaction]
    ) -> [CampusCardCostAnalyticsToolResult.CategoryCost] {
        Dictionary(grouping: transactions, by: campusCardCostType(for:))
            .map { type, groupedTransactions in
                CampusCardCostAnalyticsToolResult.CategoryCost(
                    type: type.rawValue,
                    expenseAmount: expenseAmount(of: groupedTransactions),
                    transactionCount: groupedTransactions.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.expenseAmount != rhs.expenseAmount {
                    return lhs.expenseAmount > rhs.expenseAmount
                }

                if lhs.transactionCount != rhs.transactionCount {
                    return lhs.transactionCount > rhs.transactionCount
                }

                return lhs.type.localizedStandardCompare(rhs.type) == .orderedAscending
            }
    }

    private static func makeCampusCardHourlyCosts(
        transactions: [CampusCardMergedTransaction]
    ) -> [CampusCardCostAnalyticsToolResult.HourlyCost] {
        (0...23).map { hour in
            let hourlyTransactions = transactions.filter { transaction in
                transaction.occurredAt.get(.hour) == hour
            }

            return CampusCardCostAnalyticsToolResult.HourlyCost(
                hour: hour,
                expenseAmount: expenseAmount(of: hourlyTransactions),
                transactionCount: hourlyTransactions.count
            )
        }
    }

    private static func makeCampusCardTopMerchantsByCount(
        transactions: [CampusCardMergedTransaction]
    ) -> [CampusCardCostAnalyticsToolResult.MerchantCost] {
        Dictionary(grouping: transactions, by: sanitizedCampusCardMerchantName(for:))
            .map { merchant, groupedTransactions in
                CampusCardCostAnalyticsToolResult.MerchantCost(
                    merchant: merchant,
                    expenseAmount: expenseAmount(of: groupedTransactions),
                    transactionCount: groupedTransactions.count
                )
            }
            .sorted { lhs, rhs in
                if lhs.transactionCount != rhs.transactionCount {
                    return lhs.transactionCount > rhs.transactionCount
                }

                if lhs.expenseAmount != rhs.expenseAmount {
                    return lhs.expenseAmount > rhs.expenseAmount
                }

                return lhs.merchant.localizedStandardCompare(rhs.merchant) == .orderedAscending
            }
            .prefix(5)
            .map { $0 }
    }

    private static func sanitizedCampusCardMerchantName(
        for transaction: CampusCardMergedTransaction
    ) -> String {
        let merchantName = transaction.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        return merchantName.isEmpty ? "未知商户" : merchantName
    }

    private static func campusCardCostType(
        for transaction: CampusCardMergedTransaction
    ) -> CampusCardCostType {
        if transaction.merchant.contains("充电") {
            return .charging
        }

        if transaction.merchant.contains("浴") ||
            transaction.system.contains("水控") ||
            transaction.merchant.contains("水控") {
            return .bathroom
        }

        if transaction.merchant.contains("教超") {
            return .shopping
        }

        if transaction.merchant.contains("健身") ||
            transaction.merchant.contains("教材") {
            return .entertainment
        }

        if transaction.merchant.contains(campusCardLicenseRegex) {
            return .transportation
        }

        if transaction.merchant.contains("面") ||
            transaction.merchant.contains("烧腊") ||
            transaction.merchant.contains("点心") ||
            transaction.merchant.contains("美食") ||
            transaction.merchant.contains("铁板烧") ||
            transaction.merchant.contains("牛百碗") ||
            transaction.merchant.contains("秋林") ||
            transaction.merchant.contains("麻辣香锅") ||
            transaction.merchant.contains("餐") ||
            transaction.system.contains("餐") {
            return .restaurant
        }

        return .other
    }
}
