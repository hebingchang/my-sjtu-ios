//
//  AppConfig.swift
//  MySJTU
//
//  Created by boar on 2024/11/26.
//

import Foundation
import Alamofire

private let appConfigUrl: String = "https://s3.jcloud.sjtu.edu.cn/9fd44bb76f604e8597acfcceada7cb83-tongqu/class_table/config.json"
private let scheduleSampleUrl: String = "https://s3.jcloud.sjtu.edu.cn/9fd44bb76f604e8597acfcceada7cb83-tongqu/class_table/sample_lessons.json"
private let unicodeSampleUrl: String = "https://s3.jcloud.sjtu.edu.cn/9fd44bb76f604e8597acfcceada7cb83-tongqu/class_table/sample_unicode.json"

private struct AppConfigResponse: Decodable {
    let state: Int
    let states: [String: Int]
}

class AppConfig: ObservableObject {
    enum AppStatus {
        case normal
        case review
    }

    @Published var appStatus: AppStatus
    
    init (appStatus: AppStatus) {
        self.appStatus = appStatus
    }
}

func getAppStatus() async throws -> AppConfig.AppStatus {
    let config = try await AF.request(appConfigUrl, parameters: ["r": Date.now.timeIntervalSince1970]).serializingDecodable(AppConfigResponse.self).value
    guard let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
        return .normal
    }
    if let state = config.states[build], state == 1 {
        return .review
    }
    
    return .normal
}

func getScheduleSample<T: Decodable>() async throws -> T {
    let sample = try await AF.request(scheduleSampleUrl).serializingDecodable(T.self).value
    return sample
}

func getUnicodeSample<T: Decodable>() async throws -> T {
    let sample = try await AF.request(unicodeSampleUrl).serializingDecodable(T.self).value
    return sample
}
