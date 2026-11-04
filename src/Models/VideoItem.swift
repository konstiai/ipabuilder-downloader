import Foundation
import SwiftUI

/// Repräsentiert ein heruntergeladenes Video oder eine Audiodatei in der Mediathek
public struct VideoItem: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var fileName: String
    public var relativePath: String
    public var fileSize: Int64
    public var duration: TimeInterval
    public var createdAt: Date
    public var quality: VideoQualityOption
    public var folderId: UUID?
    public var isFavorite: Bool
    public var isAudioOnly: Bool
    
    public init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        relativePath: String,
        fileSize: Int64,
        duration: TimeInterval = 0,
        createdAt: Date = Date(),
        quality: VideoQualityOption = .fullHD,
        folderId: UUID? = nil,
        isFavorite: Bool = false,
        isAudioOnly: Bool = false
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.duration = duration
        self.createdAt = createdAt
        self.quality = quality
        self.folderId = folderId
        self.isFavorite = isFavorite
        self.isAudioOnly = isAudioOnly
    }
    
    /// Ermittelt die absolute URL zur Datei im aktuellen App-Dokumentenverzeichnis
    public var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(relativePath)
    }
}

/// Benutzerdefinierter Ordner für Videos
public struct MediaFolder: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var colorHex: String
    
    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        colorHex: String = "#0A84FF"
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.colorHex = colorHex
    }
}
