//
//  Network.swift
//  MySJTU
//
//  Created by boar on 2024/11/27.
//

import Foundation
import Network
import Alamofire

enum AppUserAgent {
    static let value = "MySJTU"
}

private struct AppUserAgentInterceptor: RequestInterceptor {
    func adapt(
        _ urlRequest: URLRequest,
        for session: Session,
        completion: @escaping @Sendable (Result<URLRequest, any Error>) -> Void
    ) {
        guard urlRequest.value(forHTTPHeaderField: "User-Agent") == nil else {
            completion(.success(urlRequest))
            return
        }

        var request = urlRequest
        request.setValue(AppUserAgent.value, forHTTPHeaderField: "User-Agent")
        completion(.success(request))
    }
}

enum AppAF {
    static let cookieStorage = HTTPCookieStorage.shared

    static let session: Session = {
        let configuration = URLSessionConfiguration.af.default
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = cookieStorage
        return Session(configuration: configuration, interceptor: AppUserAgentInterceptor())
    }()
}

class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published private(set) var isConnected: Bool = false
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
