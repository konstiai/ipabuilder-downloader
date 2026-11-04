import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Hintergrund-Download Event Handler registrieren
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
}

@main
struct YoutubedownloaderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var securityManager = SecurityManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()
                
                // Biometrischer Sperrbildschirm (falls in den Einstellungen aktiviert)
                if !securityManager.isUnlocked && securityManager.isBiometricLockEnabled {
                    ZStack {
                        Color(uiColor: .systemBackground).ignoresSafeArea()
                        
                        VStack(spacing: 24) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 72))
                                .foregroundStyle(.blue)
                            
                            VStack(spacing: 8) {
                                Text("Video Saver Pro ist geschützt")
                                    .font(.title2.bold())
                                Text("Bitte bestätige deine Identität, um auf deine Downloads und Mediathek zuzugreifen.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            
                            Button {
                                securityManager.authenticateUser()
                            } label: {
                                HStack {
                                    Image(systemName: "faceid")
                                    Text("Jetzt entsperren")
                                }
                                .font(.headline)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 14)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                            .padding(.top, 12)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .background {
                    securityManager.lockApp()
                } else if phase == .active {
                    if !securityManager.isUnlocked && securityManager.isBiometricLockEnabled {
                        securityManager.authenticateUser()
                    }
                }
            }
        }
    }
}
