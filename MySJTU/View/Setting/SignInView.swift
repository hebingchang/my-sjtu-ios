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
        .task {
            do {
                authConfig = try await provider.get().getConfig(scopes: ["unicode", "card_info", "privacy"])
                stage = .waitingForWebView
                showWebView = true
            } catch {
                print(error)
                self.dismiss()
            }
        }
        .onChange(of: cookies) {
            Task {
                do {
                    let account = try await provider.get().authenticate(code: code, cookies: cookies, config: authConfig!)
                    onSuccess?(account)
                } catch {
                    print(error)
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
                url: URL(string: authConfig!.authorization_url)!,
                redirectUrl: URL(string: authConfig!.redirect_url)!,
                cookiesDomains: provider.get().cookiesDomains,
                onRedirect: { (cookies, code) in
                    self.code = code
                    self.cookies = cookies
                    stage = .exchangeToken
                    showWebView = false
                }
            )
        }
    }
}

#Preview {
    SignInView(provider: .jaccount)
}
