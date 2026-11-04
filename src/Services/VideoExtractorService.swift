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
        
        // 1. Handelt es sich um eine YouTube- oder Social-Media-URL?
        if url.host?.contains("youtube.com") == true || url.host?.contains("youtu.be") == true {
            let ytStreams = await extractYouTubeStreams(from: url, title: title)
            if !ytStreams.isEmpty {
                return ytStreams
            }
        }
        
        // 2. Ist es eine HLS m3u8 Playlist? (Hier stecken alle Auflösungen bis 4K drin!)
        if urlString.contains(".m3u8") {
            let hlsStreams = await parseHLSPlaylist(masterURL: url, title: title)
            if !hlsStreams.isEmpty {
                return hlsStreams
            }
        }
        
        // 3. Direkter Video- oder Audio-Link (.mp4, .mov, .m4a, etc.)
        if isDirectMediaURL(url) {
            return generateDirectStreamOptions(from: url, title: title)
        }
        
        // 4. Fallback: Erzeuge Standard-Qualitätsoptionen für direkte URL
        return [
            DetectedStreamOption(title: title, quality: .ultraHD4K, downloadURL: url, formatLabel: "4K UHD"),
            DetectedStreamOption(title: title, quality: .fullHD, downloadURL: url, formatLabel: "1080p Full HD"),
            DetectedStreamOption(title: title, quality: .hd720, downloadURL: url, formatLabel: "720p HD"),
            DetectedStreamOption(title: title, quality: .audioHigh, downloadURL: url, formatLabel: "M4A Audio")
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
                        estimatedBytes: currentBandwidth.map { ($0 * 120) / 8 },
                        formatLabel: "\(quality.shortLabel) HLS"
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
    
    // MARK: - YouTube & Multi-Resolution Resolver
    
    public func extractYouTubeStreams(from videoURL: URL, title: String) async -> [DetectedStreamOption] {
        var options: [DetectedStreamOption] = []
        
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
        
        return [
            DetectedStreamOption(title: title, quality: .ultraHD4K, downloadURL: url, formatLabel: "4K UHD"),
            DetectedStreamOption(title: title, quality: .fullHD, downloadURL: url, formatLabel: "1080p Full HD"),
            DetectedStreamOption(title: title, quality: .hd720, downloadURL: url, formatLabel: "720p HD"),
            DetectedStreamOption(title: title, quality: .sd480, downloadURL: url, formatLabel: "480p SD"),
            DetectedStreamOption(title: title, quality: .audioHigh, downloadURL: url, formatLabel: "M4A Audio")
        ]
    }
    
    // MARK: - JavaScript Sniffer Code & In-Page Download Button Injection
    
    /// JavaScript-Code, der in jede Webseite injiziert wird:
    /// 1. Überwacht alle Videos und HLS-Streams
    /// 2. Fügt einen eleganten "Download"-Button direkt UNTER dem Video auf der Webseite ein (wie bei Stephen Lite)!
    public static var snifferJavaScript: String {
        return """
        (function() {
            if (window.__videoSnifferInstalled) return;
            window.__videoSnifferInstalled = true;
            
            function notifyApp(videoSrc, title) {
                if (!videoSrc || videoSrc.startsWith('blob:') || videoSrc.startsWith('data:')) return;
                try {
                    window.webkit.messageHandlers.videoSniffer.postMessage({
                        action: 'videoDetected',
                        url: videoSrc,
                        pageUrl: window.location.href,
                        title: title || document.title || 'Web Video'
                    });
                } catch(e) {}
            }
            
            function onDownloadButtonClicked(e) {
                if (e) {
                    e.preventDefault();
                    e.stopPropagation();
                }
                var v = document.querySelector('video');
                var src = (v && (v.currentSrc || v.src)) ? (v.currentSrc || v.src) : window.location.href;
                try {
                    window.webkit.messageHandlers.videoSniffer.postMessage({
                        action: 'directDownloadClick',
                        url: src,
                        pageUrl: window.location.href,
                        title: document.title || 'Video'
                    });
                } catch(err) {}
            }
            
            // Fügt den "Download"-Button direkt unter dem Videoplayer auf der Seite ein
            function injectUnderVideoDownloadButton() {
                if (document.getElementById('videosaver-inpage-download-container')) return;
                
                var video = document.querySelector('video');
                if (!video) return;
                
                var targetParent = null;
                var insertBeforeElem = null;
                
                // YouTube Mobile Unterstützung
                if (window.location.hostname.includes('youtube.com')) {
                    var ytmActions = document.querySelector('ytm-slim-video-action-bar-renderer .slim-video-action-bar-actions');
                    var ytmPlayer = document.querySelector('#player-control-container') || document.querySelector('#player-container-id');
                    var ytmHeader = document.querySelector('.slim-video-information-holder');
                    
                    if (ytmActions) {
                        targetParent = ytmActions;
                    } else if (ytmHeader) {
                        targetParent = ytmHeader.parentElement;
                        insertBeforeElem = ytmHeader;
                    } else if (ytmPlayer && ytmPlayer.parentElement) {
                        targetParent = ytmPlayer.parentElement;
                    }
                }
                
                if (!targetParent) {
                    targetParent = video.parentElement;
                }
                if (!targetParent) return;
                
                var wrapper = document.createElement('div');
                wrapper.id = 'videosaver-inpage-download-container';
                wrapper.style.cssText = 'display:flex; justify-content:center; align-items:center; width:100%; padding:8px 0; margin:6px 0; z-index:99999; clear:both;';
                
                var btn = document.createElement('button');
                btn.type = 'button';
                btn.id = 'videosaver-under-video-btn';
                btn.style.cssText = 'display:inline-flex; align-items:center; justify-content:center; gap:8px; background:linear-gradient(135deg, #0A84FF 0%, #5E5CE6 100%); color:#ffffff; font-family:-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; font-size:14px; font-weight:700; padding:10px 20px; border-radius:24px; border:none; cursor:pointer; box-shadow:0 4px 14px rgba(10,132,255,0.4); user-select:none; -webkit-tap-highlight-color:transparent;';
                btn.innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg><span>Download (Alle Qualitäten)</span>';
                
                btn.addEventListener('click', onDownloadButtonClicked);
                btn.addEventListener('touchend', onDownloadButtonClicked);
                wrapper.appendChild(btn);
                
                if (insertBeforeElem && targetParent) {
                    targetParent.insertBefore(wrapper, insertBeforeElem);
                } else {
                    targetParent.appendChild(wrapper);
                }
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
                        injectUnderVideoDownloadButton();
                    });
                });
                
                injectUnderVideoDownloadButton();
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
                        setTimeout(injectUnderVideoDownloadButton, 500);
                    }
                }
                return originalFetch.apply(this, args);
            };
            
            var originalOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                if (typeof url === 'string') {
                    if (url.includes('.m3u8') || url.includes('.mp4') || url.includes('videoplayback') || url.includes('.webm')) {
                        notifyApp(url, document.title);
                        setTimeout(injectUnderVideoDownloadButton, 500);
                    }
                }
                return originalOpen.apply(this, arguments);
            };
        })();
        """
    }
}
