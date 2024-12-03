//
//  UserDefaults.swift
//  MySJTU
//
//  Created by boar on 2024/11/09.
//

import Foundation

public extension UserDefaults {
    static let shared = UserDefaults(suiteName: "group.com.boar.sjct")!
}


extension Array: @retroactive RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}
