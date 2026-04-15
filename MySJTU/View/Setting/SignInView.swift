//
//  SignInView.swift
//  MySJTU
//
//  Created by boar on 2024/09/28.
//

import SwiftUI

private enum SignInStage {
    case loadingConfig
    case waitingForWebView
    case exchangeToken
}

struct SignInView: View {
    var provider: Provider
    var onSuccess: ((WebAuthAccount) -> Void)?

    @State private var stage: SignInStage = .loadingConfig
    @State private var showWebView: Bool = false
    @State private var authConfig: OAuthConfig?
    @State private var code: String?
    @State private var cookies: [HTTPCookie] = []
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            ProgressView()
        }
        .padding()
        .analyticsScreen(
            "signin_flow",
            screenClass: "SignInView",
            parameters: [
                "provider": provider.analyticsValue
            ]
        )
        .task {
            AnalyticsService.logEvent(
                "signin_flow",
                parameters: [
                    "status": "started",
                    "provider": provider.analyticsValue
                ]
            )
            do {
                // authConfig = try await provider.get().getConfig(scopes: ["unicode", "card_info", "card_transactions", "write_card_info", "privacy"])
                authConfig = try await provider.get().getConfig(scopes: [])
                stage = .waitingForWebView
                showWebView = true
                AnalyticsService.logEvent(
                    "signin_flow",
                    parameters: [
                        "status": "config_loaded",
                        "provider": provider.analyticsValue
                    ]
                )
            } catch {
                print(error)
                AnalyticsService.logEvent(
                    "signin_flow",
                    parameters: [
                        "status": "config_failed",
                        "provider": provider.analyticsValue,
                        "error_type": AnalyticsService.errorTypeName(error)
                    ]
                )
                self.dismiss()
            }
        }
        .onChange(of: cookies) {
            Task {
                do {
                    let account = try await provider.get().authenticate(code: code, cookies: cookies, config: authConfig!)
                    AnalyticsService.logEvent(
                        "signin_flow",
                        parameters: [
                            "status": "completed",
                            "provider": provider.analyticsValue,
                            "acct_status": account.status.analyticsValue
                        ]
                    )
                    onSuccess?(account)
                } catch {
                    print(error)
                    AnalyticsService.logEvent(
                        "signin_flow",
                        parameters: [
                            "status": "auth_failed",
                            "provider": provider.analyticsValue,
                            "error_type": AnalyticsService.errorTypeName(error)
                        ]
                    )
                    self.dismiss()
                }
            }
        }
        .animation(.easeInOut, value: stage)
        .sheet(
            isPresented: $showWebView,
            onDismiss: {
                if stage != .exchangeToken {
                    self.dismiss()
                }
            }
        ) {
            BrowserView(
                urlRequest: URLRequest(url: URL(string: authConfig!.authorization_url)!),
                redirectUrl: URL(string: authConfig!.redirect_url)!,
                cookiesDomains: provider.get().cookiesDomains,
                onRedirect: { (_, cookies, code) in
                    AnalyticsService.logEvent(
                        "signin_flow",
                        parameters: [
                            "status": "callback_received",
                            "provider": provider.analyticsValue
                        ]
                    )
                    self.code = code
                    self.cookies = cookies
                    stage = .exchangeToken
                    showWebView = false
                },
                onlyCheckRedirectHost: false
            )
        }
    }
}

#Preview {
    SignInView(provider: .jaccount)
}
