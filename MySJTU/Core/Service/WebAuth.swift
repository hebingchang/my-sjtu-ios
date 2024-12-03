//
//  Service.swift
//  MySJTU
//
//  Created by boar on 2024/11/09.
//

import Foundation
import Alamofire
import SwiftSoup

enum WebAuthError: Error {
    case lessonsAuthorizeFailed
    case tokenExpired
    case tokenWithScopeNotFound
    case missingCode
    case missingOAuthConfig
    case cannotAutomaticallyRefreshSession
}

enum Provider: Codable, Identifiable {
    case jaccount
    case shsmu

    var id: Self {
        return self
    }
    
    var descriptionShort: String {
        switch self {
        case .jaccount:
            return "jAccount"
        case .shsmu:
            return "医学院"
        }
    }
    
    var description: String {
        switch self {
        case .jaccount:
            return "jAccount"
        case .shsmu:
            return "医学院用户认证中心"
        }
    }

    func get() -> WebAuthProvider {
        switch self {
        case .jaccount:
            return JAccountAuthProvider()
        case .shsmu:
            return SHSMUAuthProvider()
        }
    }
}

protocol WebAuthProvider: Codable {
    var name: String { get }
    var features: [FeatureRequirement] { get }
    var authType: WebAuthType { get }
    var cookiesDomains: [String] { get }

    func getConfig(scopes: [String]) async throws -> OAuthConfig
    func authenticate(code: String?, cookies: [HTTPCookie], config: OAuthConfig?) async throws -> WebAuthAccount
    func checkSession(cookies: [HTTPCookie]) async throws -> WebAuthStatus
    func refreshSession(account: WebAuthAccount) async throws -> WebAuthAccount
}

extension AccessToken {
    func refresh() async throws -> Self {
        let response = try await AF.request(
            "https://sjtu.azurewebsites.net/api/refreshtoken",
            method: .post,
            parameters: [
                "client_id": self.client_id,
                "refresh_token": self.refresh_token
            ],
            encoding: JSONEncoding.default
        ).serializingDecodable(ServerlessResponse<AccessToken>.self).value
        var token = response.data
        token.client_id = self.client_id

        return token
    }

    var isExpired: Bool {
        return Date(timeIntervalSince1970: TimeInterval(self.expires_at)) < Date.now
    }
}

extension WebAuthAccount {    
    func checkSession() async throws -> WebAuthStatus {
        try await self.provider.get().checkSession(cookies: self.cookies.map { cookies in
            cookies.httpCookie!
        })
    }

    func refreshSession() async throws -> Self {
        try await self.provider.get().refreshSession(account: self)
    }
}

struct JAccountAuthProvider: WebAuthProvider {
    var name: String = "jAccount"

    var features: [FeatureRequirement] = [
        FeatureRequirement(feature: .schedule, required: true),
        FeatureRequirement(feature: .unicode, required: false),
        FeatureRequirement(feature: .canvas, required: false)
    ]

    var authType: WebAuthType = .both
    
    var cookiesDomains: [String] = ["jaccount.sjtu.edu.cn"]

    func getConfig(scopes: [String]) async throws -> OAuthConfig {
        let response = try await AF.request(
            "https://sjtu.azurewebsites.net/api/getoauthconfig",
            method: .post,
            parameters: [
                "client_id": "sjtu_classtable_ng",
                "scope": scopes
            ],
            encoding: JSONEncoding.default
        ).serializingDecodable(ServerlessResponse<OAuthConfig>.self).value
        return response.data
    }

    private func authorize(code: String, config: OAuthConfig) async throws -> AccessToken {
        let response = try await AF.request(
            "https://sjtu.azurewebsites.net/api/oauthlogin",
            method: .post,
            parameters: [
                "client_id": "sjtu_classtable_ng",
                "scope": config.scopes,
                "code": code
            ],
            encoding: JSONEncoding.default
        ).serializingDecodable(ServerlessResponse<AccessToken>.self).value
        var token = response.data
        token.client_id = config.client_id

        return token
    }

    func getProfile(token: AccessToken) async throws -> Profile {
        let profileResponse = try await AF.request(
            "https://api.sjtu.edu.cn/v1/me/profile",
            parameters: [
                "access_token": token.access_token
            ],
            encoding: URLEncoding(destination: .queryString)
        ).serializingDecodable(OpenApiResponse<Profile>.self).value
        return profileResponse.entities[0]
    }

    func authenticate(code: String?, cookies: [HTTPCookie], config: OAuthConfig?) async throws -> WebAuthAccount {
        guard let code else {
            throw WebAuthError.missingCode
        }
        
        guard let config else {
            throw WebAuthError.missingOAuthConfig
        }
        
        let token = try await authorize(code: code, config: config)
        let profile = try await getProfile(token: token)

        let lessonsConfig = try await self.getConfig(scopes: ["lessons"])

        cookies.forEach { cookie in
            AF.session.configuration.httpCookieStorage?.setCookie(cookie)
        }
        let lessonsAuthorizeResponse = await AF.request(lessonsConfig.authorization_url).serializingData().response
        let query = lessonsAuthorizeResponse.response?.url?.queryDictionary

        guard let query = query else {
            throw WebAuthError.lessonsAuthorizeFailed
        }

        if let code = query["code"] {
            let lessonToken = try await authorize(code: code, config: lessonsConfig)

            return WebAuthAccount(
                authType: .both,
                provider: .jaccount,
                enabledFeatures: [
                    .schedule,
                ],
                user: profile.toWebAuthUser(),
                status: .connected,
                tokens: [
                    TokenForScopes(scopes: ["lessons"], accessToken: lessonToken),
                    TokenForScopes(scopes: config.scopes, accessToken: token),
                ],
                cookies: cookies.map { cookie in
                    Cookie(cookie)
                },
                bizData: [:]
            )
        } else {
            throw WebAuthError.lessonsAuthorizeFailed
        }
    }
    
    func checkSession(cookies: [HTTPCookie]) async throws -> WebAuthStatus {
        cookies.forEach { cookie in
            AF.session.configuration.httpCookieStorage?.setCookie(cookie)
        }
        let response = await AF.request("https://jaccount.sjtu.edu.cn/profile/api/account", method: .head)
            .serializingData()
            .response
        if let contentType = response.response?.headers.value(for: "content-type") {
            if contentType.contains("application/json") {
                return .connected
            } else if contentType.contains("text/html") {
                return .expired
            } else {
                return .error
            }
        } else {
            return .error
        }
    }

    func refreshSession(account: WebAuthAccount) async throws -> WebAuthAccount {
        var account = account
        
        for i in 0..<account.tokens.count {
            account.tokens[i].accessToken = try await account.tokens[i].accessToken.refresh()
            if account.tokens[i].scopes.contains("privacy") {
                account.user = try await getProfile(token: account.tokens[i].accessToken).toWebAuthUser()
            }
        }

        return account
    }
}


struct SHSMUAuthProvider: WebAuthProvider {
    var name: String = "医学院用户认证中心"

    var features: [FeatureRequirement] = [
        FeatureRequirement(feature: .schedule, required: true),
    ]

    var authType: WebAuthType = .cookies

    var cookiesDomains: [String] = ["shsmu.edu.cn"]

    func getConfig(scopes: [String]) async throws -> OAuthConfig {
        return OAuthConfig(
            authorization_url: "https://webvpn2.shsmu.edu.cn/login",
            authorize_url: "",
            client_id: "",
            redirect_url: "https://webvpn2.shsmu.edu.cn/",
            scopes: []
        )
    }

    func getProfile(cookies: [HTTPCookie]) async throws -> WebAuthUser {
        cookies.forEach { cookie in
            AF.session.configuration.httpCookieStorage?.setCookie(cookie)
        }

        let response = try await AF.request(
            "https://webvpn2.shsmu.edu.cn/https/77726476706e69737468656265737421f1e25594757e7b586d059ce29d51367b0014/shtyrz/login/toMain.do"
        )
            .serializingString()
            .value
        
        let doc: Document = try SwiftSoup.parse(response)
        var user = WebAuthUser(account: "", name: "", code: "")
        
        if let accountInput = try doc.select("#accountPhone").first() {
            user.account = try accountInput.attr("value")
            user.code = try accountInput.attr("value")
        }
        
        if let nameInput = try doc.select("#usernamePhone").first() {
            user.name = try nameInput.attr("value")
        }
        
        if let photoImage = try doc.select("#fileImgPhone").first() {
            user.photo = try photoImage.attr("src")
        }

        return user
    }

    func authenticate(code: String?, cookies: [HTTPCookie], config: OAuthConfig?) async throws -> WebAuthAccount {
        return WebAuthAccount(
            authType: .both,
            provider: .shsmu,
            enabledFeatures: [
                .schedule,
            ],
            user: try await getProfile(cookies: cookies),
            status: .connected,
            tokens: [],
            cookies: cookies.map { cookie in
                Cookie(cookie)
            },
            bizData: [:]
        )
    }
    
    func checkSession(cookies: [HTTPCookie]) async throws -> WebAuthStatus {
        cookies.forEach { cookie in
            AF.session.configuration.httpCookieStorage?.setCookie(cookie)
        }
        let response = await AF.request("https://webvpn2.shsmu.edu.cn/", method: .head)
            .redirect(using: .doNotFollow)
            .serializingData()
            .response
        if let response = response.response {
            if response.headers.value(for: "location") != nil {
                return .expired
            } else {
                return .connected
            }
        } else {
            return .error
        }
    }

    func refreshSession(account: WebAuthAccount) async throws -> WebAuthAccount {
        throw WebAuthError.cannotAutomaticallyRefreshSession
    }
}
