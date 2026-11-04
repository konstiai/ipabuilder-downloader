import Foundation
import SwiftUI

@MainActor
public final class DownloadManager: NSObject, ObservableObject {
    public static let shared = DownloadManager()
    
    @Published public var tasks: [DownloadTaskItem] = []
    @Published public var activeDownloadsCount: Int = 0
    
    public var backgroundCompletionHandler: (() -> Void)?
    
    private var urlSession: URLSession!
    private var taskMap: [Int: UUID] = [:] // TaskIdentifier -> Task UUID
    private var downloadTaskMap: [UUID: URLSessionDownloadTask] = [:]
    private var lastSpeedCheckMap: [UUID: (time: Date, bytes: Int64)] = [:]
    
    private let tasksStorageKey = "download_tasks_history"
    
    public override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.konsti.videosaverpro.backgrounddownloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        ]
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        loadSavedTasks()
    }
    
    // MARK: - Öffentliche Steuerung
    
    public func startDownload(
        url: URL,
        title: String,
        quality: VideoQualityOption
    ) {
        let fileExt = quality.isAudioOnly ? "m4a" : "mp4"
        let safeName = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Video" : title
        let targetFileName = "\(safeName).\(fileExt)"
        
        let item = DownloadTaskItem(
            id: UUID(),
            title: title,
            sourceURL: url,
            targetFileName: targetFileName,
            quality: quality,
            progress: 0.0,
            downloadedBytes: 0,
            totalBytes: 0,
            speedBytesPerSecond: 0,
            status: .downloading,
            createdAt: Date()
        )
        
        tasks.insert(item, at: 0)
        saveTasks()
        
        launchTask(item: item)
        AppTheme.triggerNotificationHaptic(type: .success)
    }
    
    private func launchTask(item: DownloadTaskItem) {
        var request = URLRequest(url: item.sourceURL)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        let downloadTask: URLSessionDownloadTask
        if let resumeData = item.resumeData {
            downloadTask = urlSession.downloadTask(withResumeData: resumeData)
        } else {
            downloadTask = urlSession.downloadTask(with: request)
        }
        
        taskMap[downloadTask.taskIdentifier] = item.id
        downloadTaskMap[item.id] = downloadTask
        lastSpeedCheckMap[item.id] = (Date(), item.downloadedBytes)
        
        downloadTask.resume()
        updateActiveCount()
    }
    
    public func pauseDownload(itemId: UUID) {
        guard let downloadTask = downloadTaskMap[itemId],
              let index = tasks.firstIndex(where: { $0.id == itemId }) else { return }
        
        downloadTask.cancel { [weak self] resumeData in
            Task { @MainActor in
                guard let self = self, let idx = self.tasks.firstIndex(where: { $0.id == itemId }) else { return }
                self.tasks[idx].status = .paused
                self.tasks[idx].resumeData = resumeData
                self.tasks[idx].speedBytesPerSecond = 0
                self.downloadTaskMap.removeValue(forKey: itemId)
                self.updateActiveCount()
                self.saveTasks()
            }
        }
    }
    
    public func resumeDownload(itemId: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == itemId }) else { return }
        tasks[index].status = .downloading
        saveTasks()
        launchTask(item: tasks[index])
    }
    
    public func cancelDownload(itemId: UUID) {
        if let downloadTask = downloadTaskMap[itemId] {
            downloadTask.cancel()
            downloadTaskMap.removeValue(forKey: itemId)
        }
        lastSpeedCheckMap.removeValue(forKey: itemId)
        tasks.removeAll { $0.id == itemId }
        updateActiveCount()
        saveTasks()
    }
    
    public func clearCompleted() {
        tasks.removeAll { $0.status == .completed }
        saveTasks()
    }
    
    public func retryDownload(itemId: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == itemId }) else { return }
        tasks[index].status = .downloading
        tasks[index].progress = 0
        tasks[index].downloadedBytes = 0
        tasks[index].resumeData = nil
        saveTasks()
        launchTask(item: tasks[index])
    }
    
    private func updateActiveCount() {
        activeDownloadsCount = tasks.filter { $0.status == .downloading }.count
    }
    
    // MARK: - Task Persistenz
    
    private func saveTasks() {
        if let encoded = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(encoded, forKey: tasksStorageKey)
        }
    }
    
    private func loadSavedTasks() {
        if let data = UserDefaults.standard.data(forKey: tasksStorageKey),
           let decoded = try? JSONDecoder().decode([DownloadTaskItem].self, from: data) {
            self.tasks = decoded
            for i in 0..<self.tasks.count {
                if self.tasks[i].status == .downloading {
                    self.tasks[i].status = .paused
                }
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard let itemId = self.taskMap[downloadTask.taskIdentifier],
                  let index = self.tasks.firstIndex(where: { $0.id == itemId }) else { return }
            
            self.tasks[index].downloadedBytes = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                self.tasks[index].totalBytes = totalBytesExpectedToWrite
                self.tasks[index].progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            } else {
                // Bei dynamischer Streamlänge
                self.tasks[index].progress = min(0.95, Double(totalBytesWritten) / 20_000_000.0)
            }
            
            // Download-Geschwindigkeit berechnen
            let now = Date()
            if let last = self.lastSpeedCheckMap[itemId] {
                let interval = now.timeIntervalSince(last.time)
                if interval >= 0.5 {
                    let bytesDiff = totalBytesWritten - last.bytes
                    let speed = Double(bytesDiff) / interval
                    self.tasks[index].speedBytesPerSecond = max(0, speed)
                    self.lastSpeedCheckMap[itemId] = (now, totalBytesWritten)
                }
            } else {
                self.lastSpeedCheckMap[itemId] = (now, totalBytesWritten)
            }
        }
    }
    
    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // WICHTIG: Die temporäre Datei an `location` MUSS sofort synchron gesichert werden,
        // da iOS sie nach Beenden dieser Delegate-Methode automatisch löscht!
        let tempUUID = UUID().uuidString
        let safeTempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(tempUUID).tmp")
        
        do {
            if FileManager.default.fileExists(atPath: safeTempURL.path) {
                try FileManager.default.removeItem(at: safeTempURL)
            }
            try FileManager.default.copyItem(at: location, to: safeTempURL)
        } catch {
            print("Fehler beim sofortigen Sichern der Download-Datei: \(error)")
            return
        }
        
        Task { @MainActor in
            guard let itemId = self.taskMap[downloadTask.taskIdentifier],
                  let index = self.tasks.firstIndex(where: { $0.id == itemId }) else {
                try? FileManager.default.removeItem(at: safeTempURL)
                return
            }
            
            let currentTask = self.tasks[index]
            self.tasks[index].status = .completed
            self.tasks[index].progress = 1.0
            self.tasks[index].speedBytesPerSecond = 0
            
            self.downloadTaskMap.removeValue(forKey: itemId)
            self.lastSpeedCheckMap.removeValue(forKey: itemId)
            self.updateActiveCount()
            self.saveTasks()
            
            // Datei dauerhaft im StorageManager registrieren
            let ext = currentTask.quality.isAudioOnly ? "m4a" : "mp4"
            _ = await StorageManager.shared.registerDownloadedFile(
                temporaryURL: safeTempURL,
                title: currentTask.title,
                quality: currentTask.quality,
                fileExtension: ext
            )
            
            AppTheme.triggerNotificationHaptic(type: .success)
        }
    }
    
    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            Task { @MainActor in
                guard let downloadTask = task as? URLSessionDownloadTask,
                      let itemId = self.taskMap[downloadTask.taskIdentifier],
                      let index = self.tasks.firstIndex(where: { $0.id == itemId }) else { return }
                
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return
                }
                
                self.tasks[index].status = .failed(reason: error.localizedDescription)
                self.tasks[index].speedBytesPerSecond = 0
                self.downloadTaskMap.removeValue(forKey: itemId)
                self.updateActiveCount()
                self.saveTasks()
            }
        }
    }
    
    public nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
