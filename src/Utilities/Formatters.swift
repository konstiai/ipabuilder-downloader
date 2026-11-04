import Foundation

public enum Formatters {
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
    
    public static func formatBytes(_ bytes: Int64) -> String {
        return byteCountFormatter.string(fromByteCount: bytes)
    }
    
    public static func formatSpeed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 KB/s" }
        let formatted = byteCountFormatter.string(fromByteCount: Int64(bytesPerSecond))
        return "\(formatted)/s"
    }
    
    public static func formatDuration(_ duration: TimeInterval) -> String {
        guard duration > 0, !duration.isNaN, !duration.isInfinite else { return "00:00" }
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    public static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "de_DE")
        return formatter.string(from: date)
    }
}
