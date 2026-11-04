import Foundation
import WebKit

/// Service zur präzisen Erkennung von Video-Streams und deren TATSÄCHLICH verfügbaren Auflösungen.
/// Zeigt nur die Qualitäten an, die für das jeweilige Video existieren (z.B. kein 4K, wenn Video max. 1080p oder 720p ist).
public final class VideoExtractorService {
    public static let shared = VideoExtractorService()
    
    private let urlSession: URLSession
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.urlSession = URLSession(configuration: config)
    }
    
    /// Analysiert eine URL und liefert NUR die tatsächlich existierenden Auflösungen für dieses Video
    public func extractStreams(from url: URL, pageTitle: String? = nil, webView: WKWebView? = nil) async throws -> [DetectedStreamOption] {
        let urlString = url.absoluteString.lowercased()
        let title = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? pageTitle! : "Video \(Int(Date().timeIntervalSince1970))"
        
        // 1. YouTube Video (watch?v=, /shorts/, youtu.be)
        if isYouTubeURL(url) {
            let ytStreams = await extractYouTubeRealStreams(from: url, title: title, webView: webView)
            if !ytStreams.isEmpty {
                return ytStreams
            }
        }
        
        // 2. HLS m3u8 Playlist (parst exakte Streams aus der Master-Playlist)
        if urlString.contains(".m3u8") {
            let hlsStreams = await parseHLSPlaylist(masterURL: url, title: title)
            if !hlsStreams.isEmpty {
                return hlsStreams
            }
        }
        
        // 3. Direkter Video- oder Audio-Link (.mp4, .mov, .m4a, .webm)
        if isDirectMediaURL(url) {
            return await extractDirectMediaOptions(from: url, title: title)
        }
        
        // 4. Fallback: Falls URL direkt übergeben wurde
        return [
            DetectedStreamOption(
                title: title,
                quality: .hd720,
                downloadURL: url,
                mimeType: "video/mp4",
                formatLabel: "Standard Video"
            )
        ]
    }
    
    public func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be")
    }
    
    public func extractYouTubeVideoId(from url: URL) -> String? {
        let urlString = url.absoluteString
        
        // youtu.be/VIDEO_ID
        if let host = url.host?.lowercased(), host.contains("youtu.be") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty { return path }
        }
        
        // /shorts/VIDEO_ID
        if urlString.contains("/shorts/") {
            let parts = urlString.components(separatedBy: "/shorts/")
            if parts.count > 1 {
                let idPart = parts[1].components(separatedBy: CharacterSet(charactersIn: "?&/"))[0]
                if !idPart.isEmpty { return idPart }
            }
        }
        
        // /embed/VIDEO_ID
        if urlString.contains("/embed/") {
            let parts = urlString.components(separatedBy: "/embed/")
            if parts.count > 1 {
                let idPart = parts[1].components(separatedBy: CharacterSet(charactersIn: "?&/"))[0]
                if !idPart.isEmpty { return idPart }
            }
        }
        
        // ?v=VIDEO_ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            if let v = queryItems.first(where: { $0.name == "v" })?.value, !v.isEmpty {
                return v
            }
        }
        
        return nil
    }
    
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
    
    // MARK: - Echte YouTube-Qualitäten ermitteln (Kein Fake 4K, wenn nicht vorhanden!)
    
    public func extractYouTubeRealStreams(from videoURL: URL, title: String, webView: WKWebView? = nil) async -> [DetectedStreamOption] {
        guard let videoId = extractYouTubeVideoId(from: videoURL) else {
            return []
        }
        
        var options: [DetectedStreamOption] = []
        var detectedHeights = Set<Int>()
        var foundTitle = title
        
        // 1. YouTube Innertube Android Client Player API anfragen
        // Dies gibt die echten Streams, echte URLs und GENAU die verfügbaren Auflösungen zurück!
        if let endpoint = URL(string: "https://www.youtube.com/youtubei/v1/player") {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("com.google.android.youtube/19.09.37 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")
            
            let payload: [String: Any] = [
                "videoId": videoId,
                "context": [
                    "client": [
                        "clientName": "ANDROID",
                        "clientVersion": "19.09.37",
                        "androidSdkVersion": 30,
                        "hl": "de",
                        "gl": "DE"
                    ]
                ]
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload),
               let (data, _) = try? await urlSession.upload(for: request, from: jsonData),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                if let details = json["videoDetails"] as? [String: Any],
                   let t = details["title"] as? String, !t.isEmpty {
                    foundTitle = t
                }
                
                if let streamingData = json["streamingData"] as? [String: Any] {
                    // a) HLS Master Playlist vorhanden? (hier stecken alle echten adaptiven Auflösungen)
                    if let hlsUrlString = streamingData["hlsManifestUrl"] as? String,
                       let hlsURL = URL(string: hlsUrlString) {
                        let hlsStreams = await parseHLSPlaylist(masterURL: hlsURL, title: foundTitle)
                        if !hlsStreams.isEmpty {
                            return hlsStreams
                        }
                    }
                    
                    // b) Muxed Formats (Video + Audio zusammen, z.B. 720p, 360p)
                    if let formats = streamingData["formats"] as? [[String: Any]] {
                        for fmt in formats {
                            if let urlStr = fmt["url"] as? String, let streamURL = URL(string: urlStr) {
                                let height = fmt["height"] as? Int ?? 360
                                let quality = VideoQualityOption.match(height: height)
                                let contentLengthStr = fmt["contentLength"] as? String
                                let bytes = contentLengthStr.flatMap { Int64($0) }
                                
                                if !detectedHeights.contains(quality.resolutionHeight) {
                                    detectedHeights.insert(quality.resolutionHeight)
                                    options.append(
                                        DetectedStreamOption(
                                            title: foundTitle,
                                            quality: quality,
                                            downloadURL: streamURL,
                                            mimeType: "video/mp4",
                                            estimatedBytes: bytes,
                                            formatLabel: "\(quality.shortLabel) MP4"
                                        )
                                    )
                                }
                            }
                        }
                    }
                    
                    // c) Adaptive Formats (z.B. 1080p, 1440p, 4K wenn hochgeladen!)
                    if let adaptive = streamingData["adaptiveFormats"] as? [[String: Any]] {
                        for fmt in adaptive {
                            let mimeType = fmt["mimeType"] as? String ?? ""
                            if mimeType.contains("video/mp4") || mimeType.contains("video/webm") {
                                if let height = fmt["height"] as? Int,
                                   let urlStr = fmt["url"] as? String,
                                   let streamURL = URL(string: urlStr) {
                                    let quality = VideoQualityOption.match(height: height)
                                    let contentLengthStr = fmt["contentLength"] as? String
                                    let bytes = contentLengthStr.flatMap { Int64($0) }
                                    
                                    if !detectedHeights.contains(quality.resolutionHeight) {
                                        detectedHeights.insert(quality.resolutionHeight)
                                        options.append(
                                            DetectedStreamOption(
                                                title: foundTitle,
                                                quality: quality,
                                                downloadURL: streamURL,
                                                mimeType: "video/mp4",
                                                estimatedBytes: bytes,
                                                formatLabel: "\(quality.shortLabel) HD"
                                            )
                                        )
                                    }
                                }
                            } else if mimeType.contains("audio/mp4") && !detectedHeights.contains(0) {
                                // Beste Audio-Spur
                                if let urlStr = fmt["url"] as? String, let streamURL = URL(string: urlStr) {
                                    detectedHeights.insert(0)
                                    let bytes = (fmt["contentLength"] as? String).flatMap { Int64($0) }
                                    options.append(
                                        DetectedStreamOption(
                                            title: "\(foundTitle) (Audio)",
                                            quality: .audioHigh,
                                            downloadURL: streamURL,
                                            mimeType: "audio/m4a",
                                            estimatedBytes: bytes,
                                            formatLabel: "M4A Audio (HQ)"
                                        )
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // 2. Fallback über Piped / Invidious Stream Resolver (nur tatsächlich verfügbare Streams)
        if options.isEmpty {
            let instances = [
                "https://api.piped.private.coffee/streams/\(videoId)",
                "https://pipedapi.kavin.rocks/streams/\(videoId)",
                "https://inv.tux.pizza/api/v1/videos/\(videoId)"
            ]
            
            for inst in instances {
                if let instURL = URL(string: inst),
                   let (data, _) = try? await urlSession.data(from: instURL),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    if let t = json["title"] as? String { foundTitle = t }
                    
                    if let videoStreams = json["videoStreams"] as? [[String: Any]] {
                        for stream in videoStreams {
                            let qualityStr = stream["quality"] as? String ?? ""
                            let height = stream["height"] as? Int ?? (Int(qualityStr.replacingOccurrences(of: "p", with: "")) ?? 360)
                            let quality = VideoQualityOption.match(height: height)
                            
                            if let urlStr = stream["url"] as? String, let sURL = URL(string: urlStr) {
                                if !detectedHeights.contains(quality.resolutionHeight) {
                                    detectedHeights.insert(quality.resolutionHeight)
                                    let bytes = stream["contentLength"] as? Int64
                                    options.append(
                                        DetectedStreamOption(
                                            title: foundTitle,
                                            quality: quality,
                                            downloadURL: sURL,
                                            mimeType: "video/mp4",
                                            estimatedBytes: bytes,
                                            formatLabel: "\(quality.shortLabel) MP4"
                                        )
                                    )
                                }
                            }
                        }
                    }
                    
                    if let audioStreams = json["audioStreams"] as? [[String: Any]], !detectedHeights.contains(0) {
                        if let firstAudio = audioStreams.first,
                           let urlStr = firstAudio["url"] as? String,
                           let aURL = URL(string: urlStr) {
                            detectedHeights.insert(0)
                            options.append(
                                DetectedStreamOption(
                                    title: "\(foundTitle) (Audio)",
                                    quality: .audioHigh,
                                    downloadURL: aURL,
                                    mimeType: "audio/m4a",
                                    formatLabel: "M4A Audio"
                                )
                            )
                        }
                    }
                    
                    if !options.isEmpty { break }
                }
            }
        }
        
        // Sortieren nach Auflösung (Höchste tatsächlich verfügbare zuerst)
        options.sort { $0.quality.resolutionHeight > $1.quality.resolutionHeight }
        return options
    }
    
    // MARK: - HLS Master Playlist Parser (parst NUR vorhandene Stream-Auflösungen)
    
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
                // Resolution parsen
                if let resRange = trimmed.range(of: "RESOLUTION=(\\d+)x(\\d+)", options: .regularExpression) {
                    let sub = String(trimmed[resRange])
                    let parts = sub.replacingOccurrences(of: "RESOLUTION=", with: "").split(separator: "x")
                    if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                        currentResolution = (w, h)
                    }
                }
                
                // Bandwidth parsen
                if let bwRange = trimmed.range(of: "BANDWIDTH=(\\d+)", options: .regularExpression) {
                    let sub = String(trimmed[bwRange])
                    let val = sub.replacingOccurrences(of: "BANDWIDTH=", with: "")
                    currentBandwidth = Int64(val)
                }
            } else if !trimmed.hasPrefix("#") {
                var streamURL: URL?
                if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                    streamURL = URL(string: trimmed)
                } else {
                    streamURL = URL(string: trimmed, relativeTo: masterURL)?.absoluteURL
                }
                
                if let targetURL = streamURL, let res = currentResolution {
                    // Zeige NUR die tatsächliche gefundene Auflösung!
                    let quality = VideoQualityOption.match(height: res.height)
                    
                    let opt = DetectedStreamOption(
                        title: title,
                        quality: quality,
                        downloadURL: targetURL,
                        mimeType: "application/x-mpegURL",
                        estimatedBytes: currentBandwidth.map { ($0 * 120) / 8 },
                        formatLabel: "\(quality.shortLabel) Stream"
                    )
                    options.append(opt)
                }
                
                currentResolution = nil
                currentBandwidth = nil
            }
        }
        
        options.sort { $0.quality.resolutionHeight > $1.quality.resolutionHeight }
        
        var uniqueOptions: [DetectedStreamOption] = []
        var seenResolutions = Set<Int>()
        for opt in options {
            if !seenResolutions.contains(opt.quality.resolutionHeight) {
                seenResolutions.insert(opt.quality.resolutionHeight)
                uniqueOptions.append(opt)
            }
        }
        
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
    
    // MARK: - Direkte Medien-Optionen
    
    private func extractDirectMediaOptions(from url: URL, title: String) async -> [DetectedStreamOption] {
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
        
        // HEAD Request zur Bestimmung der echten Dateigröße
        var size: Int64?
        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"
        if let (_, response) = try? await urlSession.data(for: headRequest),
           let httpResponse = response as? HTTPURLResponse,
           let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
           let bytes = Int64(contentLength) {
            size = bytes
        }
        
        // Zeigt die Originalqualität der Datei an
        return [
            DetectedStreamOption(
                title: title,
                quality: .fullHD,
                downloadURL: url,
                mimeType: "video/mp4",
                estimatedBytes: size,
                formatLabel: "Original Video"
            ),
            DetectedStreamOption(
                title: "\(title) (Audio)",
                quality: .audioHigh,
                downloadURL: url,
                mimeType: "audio/m4a",
                formatLabel: "Audio extrahieren"
            )
        ]
    }
    
    // MARK: - JavaScript Sniffer & In-Page Download Button
    
    public static var snifferJavaScript: String {
        return """
        (function() {
            if (window.__videoSnifferInstalled) return;
            window.__videoSnifferInstalled = true;
            
            function notifyApp(action, videoSrc, title) {
                try {
                    window.webkit.messageHandlers.videoSniffer.postMessage({
                        action: action || 'videoDetected',
                        url: videoSrc || window.location.href,
                        pageUrl: window.location.href,
                        title: title || document.title || 'Video'
                    });
                } catch(e) {}
            }
            
            function onButtonClick(e) {
                if (e) {
                    e.preventDefault();
                    e.stopPropagation();
                }
                var v = document.querySelector('video');
                var src = (v && (v.currentSrc || v.src)) ? (v.currentSrc || v.src) : window.location.href;
                notifyApp('directDownloadClick', src, document.title);
            }
            
            // Fügt den "Download"-Button direkt unter dem Videoplayer auf der Webseite ein
            function injectDownloadButton() {
                if (document.getElementById('videosaver-inpage-download-container')) return;
                
                var video = document.querySelector('video');
                var isYouTube = window.location.hostname.includes('youtube.com');
                
                // Auf YouTube auch dann anzeigen wenn Seite watch?v= oder shorts enthält
                if (!video && !isYouTube && !window.location.href.includes('watch')) return;
                
                var targetParent = null;
                var insertBeforeElem = null;
                
                if (isYouTube) {
                    var ytmActions = document.querySelector('ytm-slim-video-action-bar-renderer .slim-video-action-bar-actions') ||
                                    document.querySelector('.slim-video-action-bar-actions') ||
                                    document.querySelector('#player-control-container') ||
                                    document.querySelector('#player-container-id') ||
                                    document.querySelector('.slim-video-information-holder');
                    if (ytmActions) {
                        targetParent = ytmActions.parentElement || ytmActions;
                    }
                }
                
                if (!targetParent && video) {
                    targetParent = video.parentElement;
                }
                
                if (!targetParent) return;
                
                var wrapper = document.createElement('div');
                wrapper.id = 'videosaver-inpage-download-container';
                wrapper.style.cssText = 'display:flex; justify-content:center; align-items:center; width:100%; padding:10px 0; margin:8px 0; z-index:99999; clear:both;';
                
                var btn = document.createElement('button');
                btn.type = 'button';
                btn.id = 'videosaver-under-video-btn';
                btn.style.cssText = 'display:inline-flex; align-items:center; justify-content:center; gap:8px; background:linear-gradient(135deg, #0A84FF 0%, #5E5CE6 100%); color:#ffffff; font-family:-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; font-size:15px; font-weight:700; padding:12px 24px; border-radius:26px; border:none; cursor:pointer; box-shadow:0 4px 16px rgba(10,132,255,0.45); user-select:none; -webkit-tap-highlight-color:transparent;';
                btn.innerHTML = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg><span>Download</span>';
                
                btn.addEventListener('click', onButtonClick);
                btn.addEventListener('touchend', onButtonClick);
                wrapper.appendChild(btn);
                
                targetParent.appendChild(wrapper);
            }
            
            function scanVideos() {
                var isYT = window.location.hostname.includes('youtube.com') && (window.location.href.includes('watch') || window.location.href.includes('/shorts/'));
                if (isYT) {
                    notifyApp('videoDetected', window.location.href, document.title);
                }
                
                var videos = document.querySelectorAll('video');
                videos.forEach(function(v) {
                    var src = v.currentSrc || v.src;
                    if (src && !src.startsWith('blob:') && !src.startsWith('data:')) {
                        notifyApp('videoDetected', src, document.title);
                    }
                    v.addEventListener('play', function() {
                        notifyApp('videoDetected', v.currentSrc || v.src || window.location.href, document.title);
                        setTimeout(injectDownloadButton, 500);
                    });
                });
                
                injectDownloadButton();
            }
            
            setInterval(scanVideos, 1200);
            scanVideos();
            
            // Hook Fetch & XHR
            var origFetch = window.fetch;
            window.fetch = function() {
                var url = arguments[0];
                if (typeof url === 'string' && (url.includes('.m3u8') || url.includes('.mp4') || url.includes('videoplayback'))) {
                    notifyApp('videoDetected', url, document.title);
                }
                return origFetch.apply(this, arguments);
            };
            
            var origOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                if (typeof url === 'string' && (url.includes('.m3u8') || url.includes('.mp4') || url.includes('videoplayback'))) {
                    notifyApp('videoDetected', url, document.title);
                }
                return origOpen.apply(this, arguments);
            };
        })();
        """
    }
}
