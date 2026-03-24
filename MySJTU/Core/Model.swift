//
//  Model.swift
//  MySJTU
//
//  Created by boar on 2024/11/12.
//

import Foundation

extension College {
    var provider: Provider? {
        switch self {
        case .sjtu: return .jaccount
        case .sjtug: return .jaccount
        case .joint: return .jaccount
        case .shsmu: return .shsmu
        }
    }
}

enum Feature: Codable {
    case schedule
    case examAndGrade
    case unicode
    case campusCard
    case canvas

    var name: String {
        switch self {
        case .schedule: return "课程信息"
        case .examAndGrade: return "考试与成绩"
        case .unicode: return "思源码"
        case .campusCard: return "校园卡"
        case .canvas: return "在线教学平台 (Canvas)"
        }
    }
}

enum WebAuthType: Codable {
    case cookies
    case oauth
    case both
}

enum WebAuthStatus: Codable {
    case disconnected
    case connected
    case expired
    case error
}

struct FeatureRequirement: Codable {
    var feature: Feature
    var required: Bool = false
}

struct WebAuthUser: Codable {
    var account: String
    var name: String
    var code: String
    var photo: String?
    var avatar: String?
}

struct Cookie: Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
    var secure: Bool

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expires = cookie.expiresDate
        secure = cookie.isSecure
    }

    static func decode(_ data: Data) -> Cookie? {
        return try? JSONDecoder().decode(Cookie.self, from: data)
    }

    var data: Data? {
        return try? JSONEncoder().encode(self)
    }

    var httpCookie: HTTPCookie? {
        return HTTPCookie(properties: [
            HTTPCookiePropertyKey.name: name,
            HTTPCookiePropertyKey.value: value,
            HTTPCookiePropertyKey.domain: domain,
            HTTPCookiePropertyKey.path: path,
            HTTPCookiePropertyKey.expires: expires as Any,
            HTTPCookiePropertyKey.secure: secure
        ])
    }
}

struct WebAuthAccount: Codable {
    var id: String = UUID().uuidString
    var authType: WebAuthType
    var provider: Provider
    var enabledFeatures: [Feature]
    var user: WebAuthUser
    var status: WebAuthStatus
    var tokens: [TokenForScopes]
    var cookies: [Cookie]
    var bizData: [String: String]
}

struct OAuthConfig: Codable {
    var authorization_url: String
    var authorize_url: String
    var client_id: String
    var redirect_url: String
    var scopes: [String]
}

struct AccessToken: Codable {
    var client_id: String?
    var access_token: String
    var expires_in: Int
    var expires_at: Float
    var refresh_token: String
    var token_type: String
}

struct OpenApiResponse<T: Codable>: Codable {
    var entities: [T]?
    var errno: Int
    var error: String
    var total: Int
}

struct Profile: Codable {
    var id: String
    var account: String
    var accountPhotoUrl: String?
    var name: String
    var kind: String
    var code: String
    var userType: String
    var organize: Organize
    var identities: [Identity]
}

struct CardPhoto: Codable {
    var userId: String
    var url: String?
}

struct CardTransaction: Codable, Hashable {
    let dateTime: Int
    let system: String
    let merchantNo: String
    let merchant: String
    let description: String
    let amount, cardBalance: Double
}

extension Profile {
    func toWebAuthUser() -> WebAuthUser {
        var user = WebAuthUser(account: account, name: name, code: code, avatar: accountPhotoUrl)

        for identity in (self.identities.sorted {
            $0.createDate > $1.createDate
        }) {
            if identity.photoUrl != nil {
                user.photo = identity.photoUrl
                break
            }
        }

        return user
    }
}

struct Organize: Codable {
    var name: String
    var id: String
}

struct Identity: Codable {
    var kind: String
    var isDefault: Bool
    var createDate: Int
    var code: String
    var userType: String
    var userTypeName: String
    var organize: Organize
    var status: String
    var expireDate: String?
    var classNo: String?
    var admissionDate: String?
    var trainLevel: String?
    var graduateDate: String?
    var photoUrl: String?
    var type: IdentityType?
}

struct Major: Codable {
    var name: String
    var id: String
}

struct IdentityType: Codable {
    var id: String
    var name: String
}

struct TokenForScopes: Codable {
    var scopes: [String]
    var accessToken: AccessToken
}

struct ServerlessResponse<T: Codable>: Codable {
    var success: Bool
    var message: String
    var data: T
}

struct Unicode: Codable {
    let status: Int
    let code, ec: String?
    let showIcon: Bool
    let backgroundColor, messageColor, messageBackground, slowIcon: String?
    let slowMessage, slowMessageColor, slowMessageBackground: String?
}

struct UnicodeTransaction: Codable {
    let orderNo: String
    let orderTime, payTime: Int
    let merchantNo, deviceNo: String?
    let merchant: String
    let amount: Double
    let status: String
    let channel: String
}

extension UnicodeTransaction {
    func toCardTransaction() -> CardTransaction {
        CardTransaction(dateTime: self.orderTime * 1000, system: self.channel, merchantNo: self.merchantNo ?? "UNKNOWN", merchant: self.merchant, description: "思源码交易", amount: self.amount, cardBalance: 0)
    }
}

struct CampusCard: Codable {
    enum CardType: Codable {
        case general
        case working
        case undergraduate
        case master
        case doctor
    }

    struct User: Codable {
        let name, code: String
        let organize: Organize?
        let timeZone: Int
    }
    
    struct Organize: Codable {
        let name: String
    }
    
    let user: User
    let cardNo, cardId, bankNo, expireDate: String
    var cardBalance: Double
    let transBalance: Int
    let lost, frozen: Bool
    
    enum CodingKeys: String,CodingKey {
        case user, cardNo, cardId, bankNo, expireDate, cardBalance, transBalance, lost, frozen
    }
    
    var cardType: CardType = .general
}

struct CardChargeResponse: Codable {
    let cardNo: String
    let status: Status
    let applyAmount: Int
    let id: Int64
    let postData: PostData
    let applyTime, expireTime: String
    let postURL: String
    let serialNo: String

    struct Status: Codable {
        let name, code: String
    }

    enum CodingKeys: String, CodingKey {
        case cardNo, status, applyAmount, id, postData, applyTime, expireTime
        case postURL = "postUrl"
        case serialNo
    }
}

struct CardChargeStatus: Codable, Equatable, Identifiable {
    static func == (lhs: CardChargeStatus, rhs: CardChargeStatus) -> Bool {
        lhs.id == rhs.id
    }
    
    let id: Int64
    let cardNo: String
    let status: Status
    let serialNo: String
    let applyAmount: Int
    let applyTime, expireTime: String
    let failedReason: String?
    let postUrl: String?
    let postData: PostData?

    struct Status: Codable {
        let name, code: String
    }
}

struct PostData: Codable {
    let data, subsysid, sysid, sign: String
}

extension PostData {
    func toQueryString() -> String? {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "data", value: data),
            URLQueryItem(name: "subsysid", value: subsysid),
            URLQueryItem(name: "sysid", value: sysid),
            URLQueryItem(name: "sign", value: sign)
        ]
        return components.percentEncodedQuery
    }
}
