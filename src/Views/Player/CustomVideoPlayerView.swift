import SwiftUI
import AVKit

public struct CustomVideoPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    public let videoItem: VideoItem
    
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = true
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 0.0
    @State private var playbackRate: Float = 1.0
    @State private var isControlsVisible: Bool = true
    @State private var showingShareSheet: Bool = false
    @State private var saveStatusMessage: String?
    @State private var showingSaveAlert: Bool = false
    
    let playbackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    public init(videoItem: VideoItem) {
        self.videoItem = videoItem
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Player Layer
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isControlsVisible.toggle()
                        }
                    }
            } else {
                ProgressView()
                    .tint(.white)
            }
            
            // Custom Video Overlay Controls
            if isControlsVisible {
                VStack {
                    // Top Bar
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(videoItem.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            
                            HStack(spacing: 6) {
                                Text(videoItem.quality.shortLabel)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(videoItem.quality.badgeColor.opacity(0.8))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                
                                Text(Formatters.formatBytes(videoItem.fileSize))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                        
                        Spacer()
                        
                        // In Aufnahmen speichern
                        Button {
                            saveToPhotos()
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                        .padding(.trailing, 8)
                        
                        // Teilen
                        Button {
                            showingShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding()
                    .background(
                        LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                    )
                    
                    Spacer()
                    
                    // Center Controls (10s Back, Play/Pause, 10s Forward)
                    HStack(spacing: 40) {
                        Button {
                            seek(by: -10)
                        } label: {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                        
                        Button {
                            togglePlayPause()
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.white)
                        }
                        
                        Button {
                            seek(by: 10)
                        } label: {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 36))
                                .foregroundStyle(.white)
                        }
                    }
                    
                    Spacer()
                    
                    // Bottom Controls (Slider, Times & Speed Menu)
                    VStack(spacing: 8) {
                        Slider(value: $currentTime, in: 0...max(duration, 1.0)) { editing in
                            if !editing {
                                player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                            }
                        }
                        .tint(.blue)
                        
                        HStack {
                            Text(Formatters.formatDuration(currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                            
                            Spacer()
                            
                            // Speed Picker Menu
                            Menu {
                                ForEach(playbackRates, id: \.self) { rate in
                                    Button("\(String(format: "%.2fx", rate))") {
                                        setRate(rate)
                                    }
                                }
                            } label: {
                                Text("\(String(format: "%.2fx", playbackRate))")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.2))
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                            
                            Spacer()
                            
                            Text(Formatters.formatDuration(duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding()
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    )
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: [videoItem.fileURL])
        }
        .alert("Fotomediathek", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveStatusMessage ?? "")
        }
    }
    
    private func setupPlayer() {
        // AudioSession für Hintergrund-Wiedergabe konfigurieren
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        
        let p = AVPlayer(url: videoItem.fileURL)
        self.player = p
        p.play()
        self.isPlaying = true
        
        // Duration laden
        Task {
            let asset = AVURLAsset(url: videoItem.fileURL)
            if let d = try? await asset.load(.duration) {
                await MainActor.run {
                    self.duration = CMTimeGetSeconds(d)
                }
            }
        }
        
        // Time Observer
        p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { time in
            self.currentTime = CMTimeGetSeconds(time)
        }
    }
    
    private func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            p.rate = playbackRate
            isPlaying = true
        }
        AppTheme.triggerHaptic(style: .light)
    }
    
    private func seek(by seconds: Double) {
        guard let p = player else { return }
        let target = max(0, min(currentTime + seconds, duration))
        p.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        AppTheme.triggerHaptic(style: .light)
    }
    
    private func setRate(_ rate: Float) {
        self.playbackRate = rate
        player?.rate = rate
    }
    
    private func saveToPhotos() {
        Task {
            let result = await StorageManager.shared.exportToPhotoLibrary(videoItem: videoItem)
            await MainActor.run {
                switch result {
                case .success:
                    self.saveStatusMessage = "Video wurde erfolgreich in deiner Fotomediathek gespeichert!"
                    AppTheme.triggerNotificationHaptic(type: .success)
                case .failure(let error):
                    self.saveStatusMessage = "Fehler: \(error.localizedDescription)"
                    AppTheme.triggerNotificationHaptic(type: .error)
                }
                self.showingSaveAlert = true
            }
        }
    }
}
