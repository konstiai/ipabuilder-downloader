import SwiftUI
import WebKit

public struct WebViewRepresentable: UIViewRepresentable {
    @Binding public var currentURLString: String
    @Binding public var canGoBack: Bool
    @Binding public var canGoForward: Bool
    @Binding public var isLoading: Bool
    @Binding public var pageTitle: String
    @Binding public var estimatedProgress: Double
    
    public var isDesktopMode: Bool
    public var webViewAction: Binding<WebViewAction>
    public var onVideoDetected: (URL, String) -> Void
    public var onDirectDownloadRequested: (URL, String) -> Void
    
    public enum WebViewAction {
        case idle
        case goBack
        case goForward
        case reload
        case loadURL(String)
    }
    
    public init(
        currentURLString: Binding<String>,
        canGoBack: Binding<Bool>,
        canGoForward: Binding<Bool>,
        isLoading: Binding<Bool>,
        pageTitle: Binding<String>,
        estimatedProgress: Binding<Double>,
        isDesktopMode: Bool = false,
        webViewAction: Binding<WebViewAction>,
        onVideoDetected: @escaping (URL, String) -> Void,
        onDirectDownloadRequested: @escaping (URL, String) -> Void
    ) {
        self._currentURLString = currentURLString
        self._canGoBack = canGoBack
        self._canGoForward = canGoForward
        self._isLoading = isLoading
        self._pageTitle = pageTitle
        self._estimatedProgress = estimatedProgress
        self.isDesktopMode = isDesktopMode
        self.webViewAction = webViewAction
        self.onVideoDetected = onVideoDetected
        self.onDirectDownloadRequested = onDirectDownloadRequested
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "videoSniffer")
        
        let snifferScript = WKUserScript(
            source: VideoExtractorService.snifferJavaScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(snifferScript)
        configuration.userContentController = userContentController
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        context.coordinator.setupProgressObserver(for: webView)
        context.coordinator.webView = webView
        
        if let initialURL = URL(string: currentURLString) {
            webView.load(URLRequest(url: initialURL))
        }
        
        return webView
    }
    
    public func updateUIView(_ webView: WKWebView, context: Context) {
        let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.customUserAgent = isDesktopMode ? desktopUA : nil
        
        switch webViewAction.wrappedValue {
        case .goBack:
            if webView.canGoBack { webView.goBack() }
            DispatchQueue.main.async { webViewAction.wrappedValue = .idle }
        case .goForward:
            if webView.canGoForward { webView.goForward() }
            DispatchQueue.main.async { webViewAction.wrappedValue = .idle }
        case .reload:
            webView.reload()
            DispatchQueue.main.async { webViewAction.wrappedValue = .idle }
        case .loadURL(let newURLString):
            if let url = URL(string: newURLString) {
                webView.load(URLRequest(url: url))
            }
            DispatchQueue.main.async { webViewAction.wrappedValue = .idle }
        case .idle:
            break
        }
    }
    
    public class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebViewRepresentable
        weak var webView: WKWebView?
        private var progressObservation: NSKeyValueObservation?
        
        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }
        
        deinit {
            progressObservation?.invalidate()
        }
        
        func setupProgressObserver(for webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    self?.parent.estimatedProgress = view.estimatedProgress
                }
            }
        }
        
        // MARK: - Script Message Handler (Video Sniffer & In-Page Download Button)
        
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "videoSniffer",
               let body = message.body as? [String: Any] {
                
                let action = body["action"] as? String ?? "videoDetected"
                let urlString = body["url"] as? String ?? ""
                let pageUrlString = body["pageUrl"] as? String ?? ""
                let title = body["title"] as? String ?? ""
                
                // Bevorzuge YouTube/Webseiten-PageURL falls vorhanden
                let targetURL: URL?
                if pageUrlString.contains("youtube.com") || pageUrlString.contains("youtu.be") {
                    targetURL = URL(string: pageUrlString)
                } else if !urlString.isEmpty {
                    targetURL = URL(string: urlString)
                } else {
                    targetURL = URL(string: pageUrlString)
                }
                
                guard let finalURL = targetURL else { return }
                
                DispatchQueue.main.async {
                    if action == "directDownloadClick" {
                        // Der Nutzer hat direkt auf den Download-Button unter dem Video geklickt!
                        self.parent.onDirectDownloadRequested(finalURL, title)
                    } else {
                        // Normaler Hintergrund-Sniffer
                        self.parent.onVideoDetected(finalURL, title)
                    }
                }
            }
        }
        
        // MARK: - Navigation Delegate
        
        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }
        
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
                if let url = webView.url?.absoluteString {
                    self.parent.currentURLString = url
                }
                if let title = webView.title, !title.isEmpty {
                    self.parent.pageTitle = title
                }
            }
        }
        
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
    }
}
