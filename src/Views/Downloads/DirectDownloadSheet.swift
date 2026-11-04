import SwiftUI
import UIKit

public struct DirectDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var urlString: String = ""
    @State private var videoTitle: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var streamOptions: [DetectedStreamOption] = []
    @State private var errorMessage: String?
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Video-URL einfügen (YouTube, TikTok, MP4...)", text: $urlString)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        
                        Button {
                            pasteFromClipboard()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Button {
                        analyzeURL()
                    } label: {
                        HStack {
                            Spacer()
                            if isAnalyzing {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text(isAnalyzing ? "Analysiere verfügbare Qualitäten..." : "Qualitäten prüfen & anzeigen")
                                .bold()
                            Spacer()
                        }
                    }
                    .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty || isAnalyzing)
                } header: {
                    Text("Direkt-Download per Link")
                } footer: {
                    Text("Es werden nur die Qualitäten angezeigt, in denen das Video tatsächlich vorliegt (z.B. 1080p, 720p, 480p). Gibt es das Video nicht in 4K, wird 4K nicht angezeigt.")
                }
                
                if let error = errorMessage {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                
                if !streamOptions.isEmpty {
                    Section(header: Text("Tatsächlich verfügbare Qualitäten (\(streamOptions.count))")) {
                        ForEach(streamOptions) { option in
                            Button {
                                startDownload(option: option)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: option.quality.iconName)
                                        .font(.title3)
                                        .foregroundStyle(option.quality.badgeColor)
                                        .frame(width: 28)
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(option.quality.rawValue)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        
                                        HStack(spacing: 6) {
                                            Text(option.formatLabel)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            
                                            if let size = option.estimatedBytes, size > 0 {
                                                Text("• \(Formatters.formatBytes(size))")
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
                    }
                }
            }
            .navigationTitle("Link herunterladen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                checkClipboardForURL()
            }
        }
    }
    
    private func checkClipboardForURL() {
        if let clip = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !clip.isEmpty, (clip.hasPrefix("http://") || clip.hasPrefix("https://") || clip.contains("youtu")) {
            self.urlString = clip
            analyzeURL()
        }
    }
    
    private func pasteFromClipboard() {
        if let clip = UIPasteboard.general.string {
            self.urlString = clip
            analyzeURL()
        }
    }
    
    private func analyzeURL() {
        var cleanURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanURL.isEmpty else { return }
        if !cleanURL.lowercased().hasPrefix("http://") && !cleanURL.lowercased().hasPrefix("https://") {
            cleanURL = "https://\(cleanURL)"
        }
        guard let url = URL(string: cleanURL) else {
            errorMessage = "Ungültige URL"
            return
        }
        
        isAnalyzing = true
        errorMessage = nil
        streamOptions.removeAll()
        
        Task {
            do {
                let options = try await VideoExtractorService.shared.extractStreams(from: url)
                await MainActor.run {
                    self.streamOptions = options
                    self.isAnalyzing = false
                    if options.isEmpty {
                        self.errorMessage = "Keine abspielbaren Streams für diesen Link gefunden. Bitte prüfe die URL."
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Fehler: \(error.localizedDescription)"
                    self.isAnalyzing = false
                }
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
