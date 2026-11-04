import SwiftUI

public struct BrowserView: View {
    @State private var tabs: [BrowserTab] = [
        BrowserTab(title: "Google", urlString: "https://www.google.com")
    ]
    @State private var currentTabIndex: Int = 0
    @State private var addressText: String = "https://www.google.com"
    @State private var webViewAction: WebViewRepresentable.WebViewAction = .idle
    @State private var isDesktopMode: Bool = false
    @State private var estimatedProgress: Double = 0.0
    
    // Sniffer & Video State
    @State private var detectedStreams: [(url: URL, title: String)] = []
    @State private var showingDetectedSheet = false
    @State private var activeDetectedURL: URL?
    @State private var activeDetectedTitle: String = ""
    
    // Sheets
    @State private var showingTabsSheet = false
    @State private var showingBookmarksSheet = false
    
    public init() {}
    
    public var currentTab: BrowserTab {
        if tabs.indices.contains(currentTabIndex) {
            return tabs[currentTabIndex]
        }
        return BrowserTab()
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Adressleiste & Ladebalken
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: isDesktopMode ? "desktopcomputer" : "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            TextField("URL eingeben oder suchen...", text: $addressText)
                                .font(.subheadline)
                                .keyboardType(.webSearch)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit {
                                    loadAddress()
                                }
                            
                            if !addressText.isEmpty {
                                Button {
                                    addressText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        
                        Button {
                            loadAddress()
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    
                    if currentTab.isLoading && estimatedProgress < 1.0 {
                        ProgressView(value: estimatedProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                    }
                }
                .background(AppTheme.cardBackground)
                
                // Webview Bereich
                ZStack(alignment: .bottomTrailing) {
                    if tabs.indices.contains(currentTabIndex) {
                        WebViewRepresentable(
                            currentURLString: $tabs[currentTabIndex].urlString,
                            canGoBack: $tabs[currentTabIndex].canGoBack,
                            canGoForward: $tabs[currentTabIndex].canGoForward,
                            isLoading: $tabs[currentTabIndex].isLoading,
                            pageTitle: $tabs[currentTabIndex].title,
                            estimatedProgress: $estimatedProgress,
                            isDesktopMode: isDesktopMode,
                            webViewAction: $webViewAction,
                            onVideoDetected: { url, title in
                                handleVideoDetected(url: url, title: title)
                            },
                            onDirectDownloadRequested: { url, title in
                                // Sofortiger Download-Aufruf bei Klick auf den Button direkt unter dem Video
                                self.activeDetectedURL = url
                                self.activeDetectedTitle = title.isEmpty ? currentTab.title : title
                                self.showingDetectedSheet = true
                                AppTheme.triggerHaptic(style: .medium)
                            }
                        )
                        .onChange(of: tabs[currentTabIndex].urlString) { newURL in
                            self.addressText = newURL
                        }
                    }
                    
                    // Schwebender Video Download Button
                    if !detectedStreams.isEmpty {
                        Button {
                            if let last = detectedStreams.last {
                                activeDetectedURL = last.url
                                activeDetectedTitle = last.title
                                showingDetectedSheet = true
                                AppTheme.triggerHaptic(style: .medium)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.to.line.compact")
                                    .font(.headline)
                                Text("Download (\(detectedStreams.count))")
                                    .font(.subheadline.bold())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                            )
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                
                // Schnelle Video-Aktionsleiste unter dem Web-Content (wenn ein Video erkannt wurde)
                if let activeVideo = detectedStreams.last {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Video erkannt (Alle Qualitäten)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.blue)
                                .textCase(.uppercase)
                            
                            Text(activeVideo.title.isEmpty ? currentTab.title : activeVideo.title)
                                .font(.caption.bold())
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button {
                            activeDetectedURL = activeVideo.url
                            activeDetectedTitle = activeVideo.title.isEmpty ? currentTab.title : activeVideo.title
                            showingDetectedSheet = true
                            AppTheme.triggerHaptic(style: .medium)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download")
                            }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(AppTheme.primaryGradient)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // Untere Navigationsleiste
                HStack {
                    Button {
                        webViewAction = .goBack
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                    }
                    .disabled(!currentTab.canGoBack)
                    
                    Spacer()
                    
                    Button {
                        webViewAction = .goForward
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                    }
                    .disabled(!currentTab.canGoForward)
                    
                    Spacer()
                    
                    Button {
                        webViewAction = .reload
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.title3)
                    }
                    
                    Spacer()
                    
                    Button {
                        showingBookmarksSheet = true
                    } label: {
                        Image(systemName: "book")
                            .font(.title3)
                    }
                    
                    Spacer()
                    
                    Button {
                        isDesktopMode.toggle()
                        webViewAction = .reload
                        AppTheme.triggerHaptic(style: .light)
                    } label: {
                        Image(systemName: isDesktopMode ? "desktopcomputer" : "iphone")
                            .font(.title3)
                            .foregroundStyle(isDesktopMode ? .blue : .primary)
                    }
                    
                    Spacer()
                    
                    Button {
                        showingTabsSheet = true
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.primary, lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                            Text("\(tabs.count)")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(AppTheme.cardBackground)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingDetectedSheet) {
                if let url = activeDetectedURL {
                    DetectedMediaSheet(detectedURL: url, initialTitle: activeDetectedTitle)
                }
            }
            .sheet(isPresented: $showingTabsSheet) {
                TabsManagerView(tabs: $tabs, currentTabIndex: $currentTabIndex) {
                    let newTab = BrowserTab(title: "Google", urlString: "https://www.google.com")
                    tabs.append(newTab)
                    currentTabIndex = tabs.count - 1
                    addressText = newTab.urlString
                    webViewAction = .loadURL(newTab.urlString)
                }
            }
            .sheet(isPresented: $showingBookmarksSheet) {
                BookmarksView { selectedURL in
                    addressText = selectedURL
                    loadAddress()
                }
            }
        }
    }
    
    private func loadAddress() {
        var query = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        let urlToLoad: String
        if query.contains(".") && !query.contains(" ") {
            if !query.lowercased().hasPrefix("http://") && !query.lowercased().hasPrefix("https://") {
                urlToLoad = "https://\(query)"
            } else {
                urlToLoad = query
            }
        } else {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            urlToLoad = "https://www.google.com/search?q=\(encoded)"
        }
        
        if tabs.indices.contains(currentTabIndex) {
            tabs[currentTabIndex].urlString = urlToLoad
            detectedStreams.removeAll()
            webViewAction = .loadURL(urlToLoad)
        }
    }
    
    private func handleVideoDetected(url: URL, title: String) {
        if !detectedStreams.contains(where: { $0.url == url }) {
            withAnimation(.spring()) {
                detectedStreams.append((url: url, title: title.isEmpty ? currentTab.title : title))
            }
        }
    }
}
