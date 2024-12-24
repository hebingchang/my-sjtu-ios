//
//  WebView.swift
//  MySJTU
//
//  Created by boar on 2024/11/10.
//

import SwiftUI
@preconcurrency import WebKit

struct BrowserView: View {
    let urlRequest: URLRequest
    let redirectUrl: URL
    let cookiesDomains: [String]?
    let onRedirect: (_ url: URL, _ cookies: [HTTPCookie], _ code: String?) -> Void
    let onlyCheckRedirectHost: Bool
    
    @State private var webview = WKWebView()
    @State private var canGoBack: Bool = false
    @State private var canGoForward: Bool = false
    @State private var currentUrl: URL?
    @State private var isLoading: Bool = false
    @State private var estimatedProgress: Double = 0
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            WebView(
                urlRequest: urlRequest,
                redirectUrl: redirectUrl,
                cookiesDomains: cookiesDomains,
                onRedirect: onRedirect,
                onlyCheckRedirectHost: onlyCheckRedirectHost,
                wkwebView: $webview,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                currentUrl: $currentUrl,
                isLoading: $isLoading,
                estimatedProgress: $estimatedProgress
            )
            .toolbarVisibility(.visible)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar, .bottomBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        if let currentUrl {
                            Text(currentUrl.host() ?? "")
                                .font(.headline)
                        } else {
                            Text(urlRequest.url?.host() ?? "")
                                .font(.headline)
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        self.dismiss()
                    }
                    .fontWeight(.medium)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    VStack {
                        if isLoading {
                            CircularProgressView(progress: estimatedProgress)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .animation(.easeInOut, value: isLoading)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        webview.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!canGoBack)
                    .animation(.easeInOut, value: canGoBack)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        webview.goForward()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!canGoForward)
                    .animation(.easeInOut, value: canGoForward)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            //                .safeAreaInset(edge: .top) {
            //                    ProgressView(value: 0.3)
            //                        .progressViewStyle(.linear)
            //                        .frame(maxWidth: .infinity)
            //                }
            .ignoresSafeArea()
        }
    }
}

struct WebView: UIViewRepresentable {
    let urlRequest: URLRequest
    let redirectUrl: URL
    let cookiesDomains: [String]?
    let onRedirect: (_ url: URL, _ cookies: [HTTPCookie], _ code: String?) -> Void
    let onlyCheckRedirectHost: Bool
    
    @Binding var wkwebView: WKWebView
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var currentUrl: URL?
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double

    func makeUIView(context: Context) -> WKWebView {
        wkwebView.navigationDelegate = context.coordinator
        wkwebView.allowsBackForwardNavigationGestures = true
        wkwebView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoBack), options: [.new], context: nil)
        wkwebView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoForward), options: [.new], context: nil)
        wkwebView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.isLoading), options: [.new], context: nil)
        wkwebView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: [.new], context: nil)

        wkwebView.load(urlRequest)
        return wkwebView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onRedirect: onRedirect, redirectUrl: redirectUrl, cookiesDomains: cookiesDomains, onlyCheckRedirectHost: onlyCheckRedirectHost, parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onRedirect: (_ url: URL, _ cookies: [HTTPCookie], _ code: String?) -> Void
        let redirectUrl: URL
        let cookiesDomains: [String]?
        let onlyCheckRedirectHost: Bool
        let parent: WebView

        init(onRedirect: @escaping (_ url: URL, _ cookies: [HTTPCookie], _ code: String?) -> Void, redirectUrl: URL, cookiesDomains: [String]?, onlyCheckRedirectHost: Bool, parent: WebView) {
            self.onRedirect = onRedirect
            self.redirectUrl = redirectUrl
            self.cookiesDomains = cookiesDomains
            self.parent = parent
            self.onlyCheckRedirectHost = onlyCheckRedirectHost
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            if let webView = object as? WKWebView {
                DispatchQueue.main.async {
                    if keyPath == #keyPath(WKWebView.canGoBack) {
                        self.parent.canGoBack = webView.canGoBack
                    } else if keyPath == #keyPath(WKWebView.canGoForward) {
                        self.parent.canGoForward = webView.canGoForward
                    } else if keyPath == #keyPath(WKWebView.isLoading) {
                        self.parent.isLoading = webView.isLoading
                    } else if keyPath == #keyPath(WKWebView.estimatedProgress) {
                        self.parent.estimatedProgress = webView.estimatedProgress
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            self.parent.currentUrl = webView.url
                        
            if let url = navigationAction.request.url,
               (
                onlyCheckRedirectHost &&
                url.scheme == redirectUrl.scheme &&
                url.host(percentEncoded: true) == redirectUrl.host(percentEncoded: true)
               ) ||
                (
                    !onlyCheckRedirectHost &&
                    url.scheme == redirectUrl.scheme &&
                    url.host(percentEncoded: true) == redirectUrl.host(percentEncoded: true) &&
                    url.path(percentEncoded: true) == redirectUrl.path(percentEncoded: true)
                )
            {
                decisionHandler(.allow)

                let query = url.queryDictionary
                var ssoCookies: [HTTPCookie] = []
                
                guard let cookiesDomains = self.cookiesDomains else {
                    onRedirect(url, [], query["code"])
                    return
                }
                
                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies() { cookies in
                    for cookie in cookies {
                        for domain in cookiesDomains {
                            if cookie.domain.contains(domain) {
                                ssoCookies.append(cookie)
                            }
                            break
                        }
                    }
                    
                    self.onRedirect(url, ssoCookies, query["code"])
                }
            } else if let url = navigationAction.request.url, url.scheme == "alipays" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
