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
    
    private var displayHost: String {
        currentUrl?.host() ?? urlRequest.url?.host() ?? ""
    }
    
    private var progressValue: Double {
        min(max(estimatedProgress, 0), 1)
    }

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
                    VStack(spacing: isLoading ? 6 : 0) {
                        Text(displayHost)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        if isLoading {
                            ProgressView(value: progressValue)
                                .progressViewStyle(.linear)
                                .frame(width: 160)
                                .animation(.easeInOut(duration: 0.18), value: progressValue)
                                .transition(
                                    .asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)
                                    )
                                )
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
                
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        webview.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!canGoBack)
                    
                    if canGoForward {
                        Button {
                            webview.goForward()
                        } label: {
                            Image(systemName: "chevron.forward")
                        }
                    }
                }
                    
                ToolbarSpacer(placement: .bottomBar)
                
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        webview.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.parent.canGoForward = webView.canGoForward
                        }
                    } else if keyPath == #keyPath(WKWebView.isLoading) {
                        self.parent.isLoading = webView.isLoading
                    } else if keyPath == #keyPath(WKWebView.estimatedProgress) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            self.parent.estimatedProgress = webView.estimatedProgress
                        }
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
