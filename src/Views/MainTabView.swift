import SwiftUI

public struct MainTabView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @ObservedObject var storageManager = StorageManager.shared
    @State private var selectedTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            BrowserView()
                .tabItem {
                    Label("Browser", systemImage: "globe")
                }
                .tag(0)
            
            DownloadsView()
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                .badge(downloadManager.activeDownloadsCount > 0 ? "\(downloadManager.activeDownloadsCount)" : nil)
                .tag(1)
            
            LibraryView()
                .tabItem {
                    Label("Mediathek", systemImage: "film.stack")
                }
                .badge(storageManager.videos.count > 0 ? "\(storageManager.videos.count)" : nil)
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label("Einstellungen", systemImage: "gearshape")
                }
                .tag(3)
        }
    }
}
