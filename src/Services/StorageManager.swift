import Foundation
import SwiftUI
import AVFoundation
import Photos

@MainActor
public final class StorageManager: ObservableObject {
    public static let shared = StorageManager()
    
    @Published public var videos: [VideoItem] = []
    @Published public var folders: [MediaFolder] = []
    @Published public var bookmarks: [WebBookmark] = []
    
    @Published public var totalAppStorageBytes: Int64 = 0
    @Published public var freeDiskBytes: Int64 = 0
    
    private let fileManager = FileManager.default
    private let videosKey = "saved_videos_metadata"
    private let foldersKey = "saved_folders_metadata"
    private let bookmarksKey = "saved_bookmarks_metadata"
    
    public init() {
        createDirectoriesIfNeeded()
        loadMetadata()
        refreshStorageUsage()
    }
    
    public var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    public var downloadsDirectory: URL {
        documentsDirectory.appendingPathComponent("Downloads", isDirectory: true)
    }
    
    public var thumbnailsDirectory: URL {
        documentsDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    }
    
    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Metadata Persistence
    
    public func loadMetadata() {
        if let data = UserDefaults.standard.data(forKey: videosKey),
           let decoded = try? JSONDecoder().decode([VideoItem].self, from: data) {
            self.videos = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: foldersKey),
           let decoded = try? JSONDecoder().decode([MediaFolder].self, from: data) {
            self.folders = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let decoded = try? JSONDecoder().decode([WebBookmark].self, from: data) {
            self.bookmarks = decoded
        } else {
            self.bookmarks = WebBookmark.defaults
            saveBookmarks()
        }
    }
    
    public func saveVideos() {
        if let encoded = try? JSONEncoder().encode(videos) {
            UserDefaults.standard.set(encoded, forKey: videosKey)
        }
        refreshStorageUsage()
    }
    
    public func saveFolders() {
        if let encoded = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(encoded, forKey: foldersKey)
        }
    }
    
    public func saveBookmarks() {
        if let encoded = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(encoded, forKey: bookmarksKey)
        }
    }
    
    // MARK: - Video File Management
    
    /// Fügt ein erfolgreich heruntergeladenes Video aus dem temporären Pfad zur Mediathek hinzu
    public func registerDownloadedFile(
        temporaryURL: URL,
        title: String,
        quality: VideoQualityOption,
        fileExtension: String = "mp4"
    ) async -> VideoItem? {
        createDirectoriesIfNeeded()
        
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let safeName = sanitizedTitle.isEmpty ? "Video_\(Int(Date().timeIntervalSince1970))" : sanitizedTitle
        let uniqueFileName = "\(safeName)_\(UUID().uuidString.prefix(6)).\(fileExtension)"
        let destinationURL = downloadsDirectory.appendingPathComponent(uniqueFileName)
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            
            // Dateiattribute lesen
            let attrs = try fileManager.attributesOfItem(atPath: destinationURL.path)
            let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            
            // Dauer und Thumbnail asynchron generieren
            var duration: TimeInterval = 0
            let asset = AVURLAsset(url: destinationURL)
            if let durationValue = try? await asset.load(.duration) {
                duration = CMTimeGetSeconds(durationValue)
            }
            
            let isAudio = quality.isAudioOnly || ["mp3", "m4a", "aac", "wav"].contains(fileExtension.lowercased())
            
            // Thumbnail erzeugen falls Video
            let relativePath = "Downloads/\(uniqueFileName)"
            let newItem = VideoItem(
                id: UUID(),
                title: safeName,
                fileName: uniqueFileName,
                relativePath: relativePath,
                fileSize: fileSize,
                duration: duration,
                createdAt: Date(),
                quality: quality,
                folderId: nil,
                isFavorite: false,
                isAudioOnly: isAudio
            )
            
            if !isAudio {
                await generateThumbnail(for: destinationURL, itemId: newItem.id)
            }
            
            self.videos.insert(newItem, at: 0)
            self.saveVideos()
            return newItem
        } catch {
            print("Fehler beim Verschieben der Datei: \(error)")
            return nil
        }
    }
    
    /// Generiert und speichert das Thumbnail für ein Video
    public func generateThumbnail(for videoURL: URL, itemId: UUID) async {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 320)
        
        let targetThumbURL = thumbnailsDirectory.appendingPathComponent("\(itemId.uuidString).jpg")
        
        do {
            let time = CMTime(seconds: 1.0, preferredTimescale: 600)
            let (cgImage, _) = try await generator.image(at: time)
            let uiImage = UIImage(cgImage: cgImage)
            if let jpegData = uiImage.jpegData(compressionQuality: 0.8) {
                try jpegData.write(to: targetThumbURL)
            }
        } catch {
            print("Konnte Thumbnail nicht generieren: \(error)")
        }
    }
    
    public func getThumbnailImage(for item: VideoItem) -> UIImage? {
        let thumbURL = thumbnailsDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
        if let data = try? Data(contentsOf: thumbURL) {
            return UIImage(data: data)
        }
        return nil
    }
    
    public func deleteVideo(_ item: VideoItem) {
        let fileURL = item.fileURL
        try? fileManager.removeItem(at: fileURL)
        
        let thumbURL = thumbnailsDirectory.appendingPathComponent("\(item.id.uuidString).jpg")
        try? fileManager.removeItem(at: thumbURL)
        
        videos.removeAll { $0.id == item.id }
        saveVideos()
    }
    
    public func renameVideo(_ item: VideoItem, newTitle: String) {
        guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return }
        videos[index].title = newTitle
        saveVideos()
    }
    
    public func toggleFavorite(_ item: VideoItem) {
        guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return }
        videos[index].isFavorite.toggle()
        saveVideos()
    }
    
    public func moveVideo(_ item: VideoItem, toFolder folderId: UUID?) {
        guard let index = videos.firstIndex(where: { $0.id == item.id }) else { return }
        videos[index].folderId = folderId
        saveVideos()
    }
    
    // MARK: - Ordner-Management
    
    public func createFolder(name: String, colorHex: String = "#0A84FF") {
        let folder = MediaFolder(name: name, colorHex: colorHex)
        folders.append(folder)
        saveFolders()
    }
    
    public func deleteFolder(_ folder: MediaFolder) {
        // Videos aus dem Ordner in die Hauptansicht verschieben
        for i in 0..<videos.count {
            if videos[i].folderId == folder.id {
                videos[i].folderId = nil
            }
        }
        folders.removeAll { $0.id == folder.id }
        saveFolders()
        saveVideos()
    }
    
    // MARK: - In Aufnahmen / Fotomediathek speichern
    
    public func exportToPhotoLibrary(videoItem: VideoItem) async -> Result<Void, Error> {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return .failure(NSError(domain: "PhotoLibrary", code: 403, userInfo: [NSLocalizedDescriptionKey: "Zugriff auf die Fotomediathek verweigert. Bitte in den iPhone-Einstellungen aktivieren."]))
        }
        
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoItem.fileURL)
            }) { success, error in
                if success {
                    continuation.resume(returning: .success(()))
                } else {
                    continuation.resume(returning: .failure(error ?? NSError(domain: "PhotoLibrary", code: 500, userInfo: [NSLocalizedDescriptionKey: "Konnte nicht in Aufnahmen gespeichert werden."])))
                }
            }
        }
    }
    
    // MARK: - Speicher-Statistiken
    
    public func refreshStorageUsage() {
        var totalBytes: Int64 = 0
        if let enumerator = fileManager.enumerator(at: downloadsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let size = resourceValues.fileSize {
                    totalBytes += Int64(size)
                }
            }
        }
        self.totalAppStorageBytes = totalBytes
        
        if let systemAttributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = (systemAttributes[.systemFreeSize] as? NSNumber)?.int64Value {
            self.freeDiskBytes = freeSpace
        }
    }
    
    public func clearAllCache() {
        try? fileManager.removeItem(at: thumbnailsDirectory)
        createDirectoriesIfNeeded()
        refreshStorageUsage()
    }
}
