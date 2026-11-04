import Foundation
import SwiftUI

/// Repräsentiert alle verfügbaren Download-Qualitätsstufen.
/// Im Gegensatz zu "Stephen Lite" (das auf 720p limitiert ist), werden hier alle Stufen von 360p bis 4K Ultra HD & Audio unterstützt!
public enum VideoQualityOption: String, CaseIterable, Identifiable, Codable {
    case ultraHD4K = "4K Ultra HD (2160p)"
    case quadHD2K  = "2K QHD (1440p)"
    case fullHD    = "Full HD (1080p)"
    case hd720     = "HD (720p)"
    case sd480     = "SD (480p)"
    case low360    = "Standard (360p)"
    case audioHigh = "Nur Audio (HQ 320k M4A)"
    case audioStd  = "Nur Audio (Standard MP3)"
    
    public var id: String { rawValue }
    
    public var shortLabel: String {
        switch self {
        case .ultraHD4K: return "4K"
        case .quadHD2K:  return "1440p"
        case .fullHD:    return "1080p"
        case .hd720:     return "720p"
        case .sd480:     return "480p"
        case .low360:    return "360p"
        case .audioHigh: return "Audio M4A"
        case .audioStd:  return "Audio MP3"
        }
    }
    
    public var resolutionHeight: Int {
        switch self {
        case .ultraHD4K: return 2160
        case .quadHD2K:  return 1440
        case .fullHD:    return 1080
        case .hd720:     return 720
        case .sd480:     return 480
        case .low360:    return 360
        case .audioHigh, .audioStd: return 0
        }
    }
    
    public var isAudioOnly: Bool {
        return self == .audioHigh || self == .audioStd
    }
    
    public var iconName: String {
        switch self {
        case .ultraHD4K, .quadHD2K:
            return "sparkles.tv"
        case .fullHD:
            return "tv"
        case .hd720:
            return "play.rectangle"
        case .sd480, .low360:
            return "video"
        case .audioHigh, .audioStd:
            return "music.note"
        }
    }
    
    public var badgeColor: Color {
        switch self {
        case .ultraHD4K: return .purple
        case .quadHD2K:  return .indigo
        case .fullHD:    return .blue
        case .hd720:     return .cyan
        case .sd480:     return .teal
        case .low360:    return .gray
        case .audioHigh: return .orange
        case .audioStd:  return .yellow
        }
    }
    
    /// Ordnet gefundene Stream-Höhen (z.B. aus HLS Playlists oder Metadaten) der passenden Qualitätsoption zu
    public static func match(height: Int) -> VideoQualityOption {
        if height >= 2000 { return .ultraHD4K }
        if height >= 1400 { return .quadHD2K }
        if height >= 1000 { return .fullHD }
        if height >= 700  { return .hd720 }
        if height >= 450  { return .sd480 }
        return .low360
    }
}

/// Repräsentiert einen im Browser oder über Link analysierten Stream
public struct DetectedStreamOption: Identifiable, Hashable {
    public let id: UUID
    public let title: String
    public let quality: VideoQualityOption
    public let downloadURL: URL
    public let mimeType: String
    public let estimatedBytes: Int64?
    public let formatLabel: String
    
    public init(
        id: UUID = UUID(),
        title: String,
        quality: VideoQualityOption,
        downloadURL: URL,
        mimeType: String = "video/mp4",
        estimatedBytes: Int64? = nil,
        formatLabel: String = "MP4"
    ) {
        self.id = id
        self.title = title
        self.quality = quality
        self.downloadURL = downloadURL
        self.mimeType = mimeType
        self.estimatedBytes = estimatedBytes
        self.formatLabel = formatLabel
    }
}
