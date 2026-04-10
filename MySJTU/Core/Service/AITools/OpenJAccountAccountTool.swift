//
//  OpenJAccountAccountTool.swift
//  MySJTU
//
//  Created by boar on 2026/04/06.
//

import Foundation

extension AIService {
    final class OpenJAccountAccountToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "open_jaccount_account_view",
                displayName: "打开 jAccount 账户页面",
                category: .navigation,
                functionDescription: "当用户明确要求登录 jAccount、打开 jAccount 账户设置、管理 jAccount 账号状态时，打开 app 内的 jAccount 账户页面。",
                parametersSchema: .emptyObject,
                isAvailableInChat: true,
                requiresUserAuthorization: false
            )
        }

        override func execute(
            argumentsJSON: String,
            toolNavigationHandler: ToolNavigationHandler?
        ) async -> String {
            await toolNavigationHandler?(.jAccountAccount)
            return AIService.encodeToolExecutionResult(
                OpenJAccountAccountToolResult(
                    destination: AIToolNavigationDestination.jAccountAccount.rawValue
                )
            )
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            .init(
                text: "正在打开“jAccount 账户”",
                functionName: functionName,
                category: category,
                invocationKey: functionName
            )
        }
    }

    final class UserProfileToolDefinition: ToolDefinition, @unchecked Sendable {
        init() {
            super.init(
                functionName: "get_user_profile",
                displayName: "获取用户信息",
                category: .query,
                functionDescription: "获取当前 jAccount 用户的精简个人信息。该工具直接调用 getProfile()，仅返回姓名，以及 status 为“正常”的身份中的学号/工号、用户类型、学院或单位、班级、入学日期、培养层次和毕业日期；若这些字段缺失，则不会返回对应字段。",
                parametersSchema: .emptyObject,
                isAvailableInChat: true
            )
        }

        override func execute(argumentsJSON: String) async -> String {
            do {
                let result = try await AIService.fetchUserProfileResult()
                return AIService.encodeToolExecutionResult(result)
            } catch {
                return AIService.encodeToolExecutionError(
                    .init(error: AIService.userProfileToolErrorText(error))
                )
            }
        }

        override func invocationStatusPayload(argumentsJSON: String) async -> ToolStatusPayload {
            .init(
                text: "已调用“获取用户信息”",
                functionName: functionName,
                category: category,
                invocationKey: functionName
            )
        }
    }
}

extension AIService {
    static func currentJAccount(
        userDefaults: UserDefaults = .standard
    ) -> WebAuthAccount? {
        let accounts = storedAccounts(userDefaults: userDefaults)

        return accounts.first { $0.provider == .jaccount && $0.status == .connected }
            ?? accounts.first { $0.provider == .jaccount }
    }

    static func fetchUserProfileResult(
        userDefaults: UserDefaults = .standard
    ) async throws -> UserProfileToolResult {
        guard let account = currentJAccount(userDefaults: userDefaults) else {
            throw APIError.noAccount
        }

        let profile = try await SJTUOpenAPI(tokens: account.tokens).getProfile()
        return makeUserProfileToolResult(from: profile)
    }

    static func makeUserProfileToolResult(from profile: Profile) -> UserProfileToolResult {
        let normalIdentity = preferredNormalIdentity(from: profile.identities)

        return UserProfileToolResult(
            name: sanitizedUserProfileValue(profile.name),
            code: normalIdentity.flatMap { sanitizedUserProfileValue($0.code) },
            userTypeName: normalIdentity.flatMap { sanitizedUserProfileValue($0.userTypeName) },
            organize: normalIdentity.flatMap { sanitizedUserProfileValue($0.organize.name) },
            classNo: normalIdentity.flatMap { sanitizedUserProfileValue($0.classNo) },
            admissionDate: normalIdentity.flatMap { sanitizedUserProfileValue($0.admissionDate) },
            trainLevel: normalIdentity.flatMap { sanitizedUserProfileValue($0.trainLevel) },
            graduateDate: normalIdentity.flatMap { sanitizedUserProfileValue($0.graduateDate) }
        )
    }

    static func preferredNormalIdentity(from identities: [Identity]) -> Identity? {
        identities
            .filter { sanitizedUserProfileValue($0.status) == "正常" }
            .sorted { lhs, rhs in
                // Prefer the default active identity when a user has multiple normal identities.
                if lhs.isDefault != rhs.isDefault {
                    return lhs.isDefault && !rhs.isDefault
                }

                if lhs.createDate != rhs.createDate {
                    return lhs.createDate > rhs.createDate
                }

                return lhs.code.localizedStandardCompare(rhs.code) == .orderedAscending
            }
            .first
    }

    static func sanitizedUserProfileValue(_ value: String?) -> String? {
        guard let trimmedValue = value?.trimSpace(), !trimmedValue.isEmpty else {
            return nil
        }

        return trimmedValue
    }

    static func userProfileToolErrorText(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .sessionExpired, .noAccount:
                return "jAccount 登录状态可能已失效，请前往账户页重新登录。"
            case .remoteError(let message), .runtimeError(let message):
                return message
            case .internalError:
                return "无法获取用户信息，请稍后重试。"
            }
        }

        if let authError = error as? WebAuthError {
            switch authError {
            case .tokenWithScopeNotFound:
                return "当前 jAccount 缺少用户信息权限，请在账户页中重新登录后再试。"
            case .tokenExpired:
                return "jAccount 令牌已过期，请在账户页中重新登录后再试。"
            default:
                break
            }
        }

        return "无法获取用户信息，请稍后重试。"
    }
}
