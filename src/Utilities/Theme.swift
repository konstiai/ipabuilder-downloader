import SwiftUI

public enum AppTheme {
    public static let primaryGradient = LinearGradient(
        colors: [Color.blue, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let accentGradient = LinearGradient(
        colors: [Color.cyan, Color.blue],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    public static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    public static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    
    public static func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    public static func triggerNotificationHaptic(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}
