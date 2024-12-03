//
//  URL.swift
//  MySJTU
//
//  Created by boar on 2024/11/10.
//

import Foundation

extension URL {
    var queryDictionary: [String: String] {
        var dict: [String: String] = [:]
        let items = URLComponents(string: absoluteString)?.queryItems ?? []
        items.forEach {
            dict.updateValue($0.value ?? "", forKey: $0.name)
        }
        return dict
    }
}
