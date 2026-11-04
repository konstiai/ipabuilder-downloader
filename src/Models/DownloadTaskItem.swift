import Foundation
import SwiftUI

public enum DownloadStatus: Equatable, Codable {
    case waiting
    case downloading
    case paused
    case completed
    case failed(reason: String)
    
    public var label: String {
        switch self {
        case .waiting: return "Warteschlange"
        case .downloading: return "Lädt herunter..."
        case .paused: return "Pausiert"
        case .completed: return "Abgeschlossen"
        case .failed(let reason): return "Fehler: \(reason)"
        }
    }
    
    public var iconName: String {
        switch self {
        case .waiting: return "clock"
        case .downloading: return "arrow.down.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    
    public var color: Color {
        switch self {
        case .waiting: return .secondary
        case .downloading: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}

public struct DownloadTaskItem: Identifiable, Codable {
    public let id: UUID
    public var title: String
    public var sourceURL: URL
    public var targetFileName: String
    public var quality: VideoQualityOption
    public var progress: Double // 0.0 ... 1.0
    public var downloadedBytes: Int64
    public var totalBytes: Int64
    public var speedBytesPerSecond: Double
    public var status: DownloadStatus
    public var createdAt: Date
    public var resumeData: Data?
    
    public init(
        id: UUID = UUID(),
        title: String,
        sourceURL: URL,
        targetFileName: String,
        quality: VideoQualityOption = .fullHD,
        progress: Double = 0.0,
        downloadedBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        speedBytesPerSecond: Double = 0.0,
        status: DownloadStatus = .waiting,
        createdAt: Date = Date(),
        resumeData: Data? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.targetFileName = targetFileName
        self.quality = quality
        self.progress = progress
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
        self.status = status
        self.createdAt = createdAt
        self.resumeData = resumeData
    }
}
