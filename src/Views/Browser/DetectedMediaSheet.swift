import SwiftUI

public struct DetectedMediaSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    public let detectedURL: URL
    public let initialTitle: String
    
    @State private var videoTitle: String
    @State private var availableOptions: [DetectedStreamOption] = []
    @State private var isAnalyzing: Bool = true
    @State private var errorMessage: String?
    
    public init(detectedURL: URL, initialTitle: String) {
        self.detectedURL = detectedURL
        self.initialTitle = initialTitle
        self._videoTitle = State(initialValue: initialTitle.isEmpty ? "Video \(Int(Date().timeIntervalSince1970))" : initialTitle)
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Video Header & Titel
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "film.stack.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 54, height: 54)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Video erkannt")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                                .textCase(.uppercase)
                            
                            TextField("Videotitel anpassen...", text: $videoTitle)
                                .font(.headline)
                                .textFieldStyle(.plain)
                        }
                    }
                    .padding()
                    .background(AppTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding()
                
                Divider()
                
                if isAnalyzing {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Ermittle verfügbare Video-Qualitäten...")
                            .font(.subheadline.bold())
                        Text("Prüfe, in welchen Auflösungen dieses Video tatsächlich verfügbar ist.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableOptions.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        Text("Keine Streams gefunden")
                            .font(.headline)
                        Text(errorMessage ?? "Für dieses Video konnten keine direkten Streams geladen werden.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Button {
                            Task { await loadStreams() }
                        } label: {
                            Label("Erneut versuchen", systemImage: "arrow.clockwise")
                                .font(.subheadline.bold())
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(availableOptions) { option in
                                Button {
                                    startDownload(option: option)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: option.quality.iconName)
                                            .font(.title2)
                                            .foregroundStyle(option.quality.badgeColor)
                                            .frame(width: 32)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Text(option.quality.rawValue)
                                                    .font(.headline)
                                                    .foregroundStyle(.primary)
                                                
                                                if option.quality == .ultraHD4K || option.quality == .quadHD2K || option.quality == .fullHD {
                                                    Text("HD")
                                                        .font(.system(size: 10, weight: .bold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.blue.opacity(0.15))
                                                        .foregroundStyle(.blue)
                                                        .clipShape(Capsule())
                                                }
                                            }
                                            
                                            HStack(spacing: 6) {
                                                Text(option.formatLabel)
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.secondary.opacity(0.15))
                                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                                
                                                if let size = option.estimatedBytes, size > 0 {
                                                    Text(Formatters.formatBytes(size))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.blue)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            Text("Tatsächlich verfügbare Qualitäten (\(availableOptions.count))")
                        } footer: {
                            Text("Es werden nur Qualitäten aufgeführt, in denen das Video vom Ersteller hochgeladen wurde. Auflösungen, die nicht existieren (z.B. 4K bei reinen 1080p-Videos), werden ausgeblendet.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Download-Optionen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadStreams()
            }
        }
    }
    
    private func loadStreams() async {
        isAnalyzing = true
        errorMessage = nil
        do {
            let options = try await VideoExtractorService.shared.extractStreams(from: detectedURL, pageTitle: initialTitle)
            await MainActor.run {
                self.availableOptions = options
                self.isAnalyzing = false
                if options.isEmpty {
                    self.errorMessage = "Es konnten keine abspielbaren Videoformate geladen werden."
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }
    
    private func startDownload(option: DetectedStreamOption) {
        DownloadManager.shared.startDownload(
            url: option.downloadURL,
            title: videoTitle.isEmpty ? option.title : videoTitle,
            quality: option.quality
        )
        dismiss()
    }
}
