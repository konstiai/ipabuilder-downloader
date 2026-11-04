import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
public final class SecurityManager: ObservableObject {
    public static let shared = SecurityManager()
    
    @AppStorage("isBiometricLockEnabled") public var isBiometricLockEnabled: Bool = false
    @Published public var isUnlocked: Bool = true
    
    public init() {
        if isBiometricLockEnabled {
            self.isUnlocked = false
        }
    }
    
    public func authenticateUser() {
        guard isBiometricLockEnabled else {
            isUnlocked = true
            return
        }
        
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Entsperre deine geschützten Videos und Downloads"
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, authenticationError in
                Task { @MainActor in
                    if success {
                        self?.isUnlocked = true
                        AppTheme.triggerNotificationHaptic(type: .success)
                    } else {
                        self?.isUnlocked = false
                        AppTheme.triggerNotificationHaptic(type: .error)
                    }
                }
            }
        } else {
            // Kein Passcode eingerichtet, Zugriff erlauben
            isUnlocked = true
        }
    }
    
    public func lockApp() {
        if isBiometricLockEnabled {
            isUnlocked = false
        }
    }
}
