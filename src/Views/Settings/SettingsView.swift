import SwiftUI
import WebKit

public struct SettingsView: View {
    @ObservedObject var storageManager = StorageManager.shared
    @ObservedObject var securityManager = SecurityManager.shared
    
    @AppStorage("defaultQualitySetting") private var defaultQuality: String = "Immer fragen"
    @AppStorage("downloadOnlyWiFi") private var downloadOnlyWiFi: Bool = false
    @AppStorage("maxConcurrentDownloads") private var maxConcurrentDownloads: Int = 3
    
    @State private var showingClearCacheAlert = false
    @State private var cacheClearedToast = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                // Download-Einstellungen
                Section(header: Text("Download-Einstellungen")) {
                    Picker("Standard-Qualität", selection: $defaultQuality) {
                        Text("Immer fragen").tag("Immer fragen")
                        Text("4K Ultra HD (2160p)").tag("4K")
                        Text("Full HD (1080p)").tag("1080p")
                        Text("HD (720p)").tag("720p")
                        Text("Nur Audio").tag("Audio")
                    }
                    
                    Toggle(isOn: $downloadOnlyWiFi) {
                        Label("Nur über WLAN herunterladen", systemImage: "wifi")
                    }
                    
                    Stepper("Gleichzeitige Downloads: \(maxConcurrentDownloads)", value: $maxConcurrentDownloads, in: 1...5)
                }
                
                // Sicherheit & Privatsphäre (Stephen Lite Feature)
                Section(header: Text("Sicherheit & Privatsphäre")) {
                    Toggle(isOn: $securityManager.isBiometricLockEnabled) {
                        Label("Mit Face ID / Code sperren", systemImage: "faceid")
                    }
                    .onChange(of: securityManager.isBiometricLockEnabled) { enabled in
                        if enabled {
                            securityManager.authenticateUser()
                        }
                    }
                    
                    Button(role: .destructive) {
                        showingClearCacheAlert = true
                    } label: {
                        Label("Browser-Cache & Cookies löschen", systemImage: "trash")
                    }
                }
                
                // Speicherplatz
                Section(header: Text("Speicherplatz")) {
                    HStack {
                        Label("Von Videos belegt", systemImage: "internaldrive")
                        Spacer()
                        Text(Formatters.formatBytes(storageManager.totalAppStorageBytes))
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Freier iPhone-Speicher", systemImage: "iphone")
                        Spacer()
                        Text(Formatters.formatBytes(storageManager.freeDiskBytes))
                            .foregroundStyle(.secondary)
                    }
                    
                    Button("Thumbnail-Cache bereinigen") {
                        storageManager.clearAllCache()
                        AppTheme.triggerNotificationHaptic(type: .success)
                    }
                }
                
                // Über die App
                Section(header: Text("Über die App")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (Build 1)")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Kompatibilität")
                        Spacer()
                        Text("iOS 16 - iOS 18+")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Optimiert für")
                        Spacer()
                        Text("iPhone 11 - 15 Pro Max")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .alert("Cache löschen", isPresented: $showingClearCacheAlert) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    clearBrowserCache()
                }
            } message: {
                Text("Möchtest du alle Webseiten-Daten, Cache und Cookies im integrierten Browser bereinigen?")
            }
        }
    }
    
    private func clearBrowserCache() {
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: types, modifiedSince: Date.distantPast) {
            DispatchQueue.main.async {
                AppTheme.triggerNotificationHaptic(type: .success)
            }
        }
    }
}
