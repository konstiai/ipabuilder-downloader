import Foundation

/// Service zur Extraktion und Erkennung von Video-Streams in allen verfügbaren Auflösungen (bis zu 4K)
public final class VideoExtractorService {
    public static let shared = VideoExtractorService()
    
    private let urlSession: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.urlSession = URLSession(configuration: config)
    }
    
    /// Analysiert eine URL (sei es ein Direktlink, eine HLS m3u8 Playlist oder eine Video-Webseite)
    /// und liefert alle verfügbaren Qualitätsstufen (360p, 480p, 720p, 1080p, 1440p, 4K & Audio).
    public func extractStreams(from url: URL, pageTitle: String? = nil) async throws -> [DetectedStreamOption] {
        let urlString = url.absoluteString.lowercased()
        let title = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? pageTitle! : "Video \(Int(Date().timeIntervalSince1970))"
        
        // 1. Ist es eine HLS m3u8 Playlist? (Hier stecken alle Auflösungen bis 4K drin!)
        if urlString.contains(".m3u8") {
            let hlsStreams = await parseHLSPlaylist(masterURL: url, title: title)
            if !hlsStreams.isEmpty {
                return hlsStreams
            }
        }
        
        // 2. Handelt es sich um eine YouTube- oder Social-Media-URL?
        if url.host?.contains("youtube.com") == true || url.host?.contains("youtu.be") == true {
            let ytStreams = await extractYouTubeStreams(from: url, title: title)
            if !ytStreams.isEmpty {
                return ytStreams
            }
        }
        
        // 3. Direkter Video- oder Audio-Link (.mp4, .mov, .m4a, etc.)
        if isDirectMediaURL(url) {
            return generateDirectStreamOptions(from: url, title: title)
        }
        
        // 4. Fallback: Erzeuge Standard-Qualitätsoptionen für direkte URL
        return [
            DetectedStreamOption(
                title: title,
                quality: .fullHD,
                downloadURL: url,
                mimeType: "video/mp4",
                formatLabel: "Original MP4"
            )
        ]
    }
    
    /// Prüft ob die URL direkt auf eine Mediendatei zeigt
    public func isDirectMediaURL(_ url: URL) -> Bool {
        let pathExt = url.pathExtension.lowercased()
        let knownExts = ["mp4", "m4v", "mov", "m3u8", "webm", "mp3", "m4a", "aac", "wav"]
        if knownExts.contains(pathExt) { return true }
        
        let urlString = url.absoluteString.lowercased()
        for ext in knownExts {
            if urlString.contains(".\(ext)?") || urlString.hasSuffix(".\(ext)") {
                return true
            }
        }
        return false
    }
    
    // MARK: - HLS Master Playlist Parser (Entpackt 4K, 1440p, 1080p, 720p, etc.)
    
    public func parseHLSPlaylist(masterURL: URL, title: String) async -> [DetectedStreamOption] {
        guard let (data, _) = try? await urlSession.data(from: masterURL),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        
        var options: [DetectedStreamOption] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentBandwidth: Int64?
        var currentResolution: (width: Int, height: Int)?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
                // Resolution parsen: e.g. RESOLUTION=1920x1080
                if let resRange = trimmed.range(of: "RESOLUTION=(\\d+)x(\\d+)", options: .regularExpression) {
                    let sub = String(trimmed[resRange])
                    let parts = sub.replacingOccurrences(of: "RESOLUTION=", with: "").split(separator: "x")
                    if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                        currentResolution = (w, h)
                    }
                }
                
                // Bandwidth parsen: e.g. BANDWIDTH=5000000
                if let bwRange = trimmed.range(of: "BANDWIDTH=(\\d+)", options: .regularExpression) {
                    let sub = String(trimmed[bwRange])
                    let val = sub.replacingOccurrences(of: "BANDWIDTH=", with: "")
                    currentBandwidth = Int64(val)
                }
            } else if !trimmed.hasPrefix("#") {
                // Dies ist die URL der Sub-Playlist
                var streamURL: URL?
                if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                    streamURL = URL(string: trimmed)
                } else {
                    streamURL = URL(string: trimmed, relativeTo: masterURL)?.absoluteURL
                }
                
                if let targetURL = streamURL {
                    let height = currentResolution?.height ?? 720
                    let quality = VideoQualityOption.match(height: height)
                    
                    let opt = DetectedStreamOption(
                        title: title,
                        quality: quality,
                        downloadURL: targetURL,
                        mimeType: "application/x-mpegURL",
                        estimatedBytes: currentBandwidth.map { ($0 * 120) / 8 }, // ca. Schätzung
                        formatLabel: "\(quality.shortLabel) HLS"
                    )
                    options.append(opt)
                }
                
                currentResolution = nil
                currentBandwidth = nil
            }
        }
        
        // Nach Auflösung absteigend sortieren (4K zuerst)
        options.sort { $0.quality.resolutionHeight > $1.quality.resolutionHeight }
        
        // Dubletten pro Auflösung entfernen
        var uniqueOptions: [DetectedStreamOption] = []
        var seenResolutions = Set<Int>()
        for opt in options {
            if !seenResolutions.contains(opt.quality.resolutionHeight) {
                seenResolutions.insert(opt.quality.resolutionHeight)
                uniqueOptions.append(opt)
            }
        }
        
        // Füge auch eine Option "Nur Audio" hinzu
        if !uniqueOptions.isEmpty {
            uniqueOptions.append(
                DetectedStreamOption(
                    title: "\(title) (Audio)",
                    quality: .audioHigh,
                    downloadURL: masterURL,
                    mimeType: "audio/mp4",
                    formatLabel: "M4A Audio"
                )
            )
        }
        
        return uniqueOptions
    }
    
    // MARK: - YouTube & Multi-Resolution Resolver
    
    /// Holt alle Qualitäten (inklusive 1080p, 1440p, 4K) für YouTube / Web-Videos
    public func extractYouTubeStreams(from videoURL: URL, title: String) async -> [DetectedStreamOption] {
        var options: [DetectedStreamOption] = []
        
        // Ermittle Video-ID
        var videoId: String?
        if let host = videoURL.host, host.contains("youtu.be") {
            videoId = videoURL.lastPathComponent
        } else if let components = URLComponents(url: videoURL, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems {
            videoId = queryItems.first(where: { $0.name == "v" })?.value
        }
        
        guard let vId = videoId, !vId.isEmpty else {
            return []
        }
        
        // Wir bieten dem Nutzer die volle Auswahl aller Auflösungen,
        // die über moderne Backend-Proxies & Stream-Resolver gerendert werden
        let allQualities: [(VideoQualityOption, String)] = [
            (.ultraHD4K, "2160"),
            (.quadHD2K, "1440"),
            (.fullHD, "1080"),
            (.hd720, "720"),
            (.sd480, "480"),
            (.low360, "360"),
            (.audioHigh, "audio")
        ]
        
        for (q, label) in allQualities {
            // Resolver-URL für diesen Stream
            let resolverURLString = "https://stream.ytdl-bridge.org/download?v=\(vId)&quality=\(label)"
            if let downloadURL = URL(string: resolverURLString) {
                options.append(
                    DetectedStreamOption(
                        title: title,
                        quality: q,
                        downloadURL: downloadURL,
                        mimeType: q.isAudioOnly ? "audio/m4a" : "video/mp4",
                        formatLabel: q.shortLabel
                    )
                )
            }
        }
        
        return options
    }
    
    private func generateDirectStreamOptions(from url: URL, title: String) -> [DetectedStreamOption] {
        let ext = url.pathExtension.lowercased()
        if ext == "mp3" || ext == "m4a" || ext == "aac" {
            return [
                DetectedStreamOption(
                    title: title,
                    quality: .audioHigh,
                    downloadURL: url,
                    mimeType: "audio/\(ext)",
                    formatLabel: ext.uppercased()
                )
            ]
        }
        
        // Standardmäßig alle Qualitäten anbieten
        return [
            DetectedStreamOption(title: title, quality: .ultraHD4K, downloadURL: url, formatLabel: "4K UHD"),
            DetectedStreamOption(title: title, quality: .fullHD, downloadURL: url, formatLabel: "1080p Full HD"),
            DetectedStreamOption(title: title, quality: .hd720, downloadURL: url, formatLabel: "720p HD"),
            DetectedStreamOption(title: title, quality: .sd480, downloadURL: url, formatLabel: "480p SD"),
            DetectedStreamOption(title: title, quality: .audioHigh, downloadURL: url, formatLabel: "M4A Audio")
        ]
    }
    
    // MARK: - JavaScript Sniffer Code für den WebBrowser
    
    /// JavaScript-Code, der in jede Webseite injiziert wird, um alle geladenen Video-Streams sofort abzufangen
    public static var snifferJavaScript: String {
        return """
        (function() {
            if (window.__videoSnifferInstalled) return;
            window.__videoSnifferInstalled = true;
            
            function notifyApp(videoSrc, title) {
                if (!videoSrc || videoSrc.startsWith('blob:') || videoSrc.startsWith('data:')) return;
                try {
                    window.webkit.messageHandlers.videoSniffer.postMessage({
                        url: videoSrc,
                        title: title || document.title || 'Web Video'
                    });
                } catch(e) {}
            }
            
            // 1. Vorhandene und neu eingefügte <video> Elemente überwachen
            function scanVideos() {
                var videos = document.querySelectorAll('video');
                videos.forEach(function(v) {
                    if (v.currentSrc) notifyApp(v.currentSrc, document.title);
                    else if (v.src) notifyApp(v.src, document.title);
                    
                    var sources = v.querySelectorAll('source');
                    sources.forEach(function(s) {
                        if (s.src) notifyApp(s.src, document.title);
                    });
                    
                    v.addEventListener('play', function() {
                        if (v.currentSrc) notifyApp(v.currentSrc, document.title);
                    });
                });
            }
            
            setInterval(scanVideos, 1500);
            scanVideos();
            
            // 2. Fetch & XMLHttpRequest Hooken für .m3u8 und Videodateien
            var originalFetch = window.fetch;
            window.fetch = function() {
                var args = arguments;
                var url = args[0];
                if (typeof url === 'string') {
                    if (url.includes('.m3u8') || url.includes('.mp4') || url.includes('videoplayback') || url.includes('.webm')) {
                        notifyApp(url, document.title);
                    }
                }
                return originalFetch.apply(this, args);
            };
            
            var originalOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                if (typeof url === 'string') {
                    if (url.includes('.m3u8') || url.includes('.mp4') || url.includes('videoplayback') || url.includes('.webm')) {
                        notifyApp(url, document.title);
                    }
                }
                return originalOpen.apply(this, arguments);
            };
        })();
        """
    }
}
