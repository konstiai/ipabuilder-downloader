import SwiftUI

public struct FolderDetailView: View {
    @Environment(\.dismiss) private var dismiss
    public let folder: MediaFolder
    @ObservedObject var storageManager = StorageManager.shared
    
    @State private var selectedVideoForPlay: VideoItem?
    @State private var shareURL: URL?
    @State private var showingShareSheet = false
    @State private var videoToRename: VideoItem?
    @State private var renameText = ""
    @State private var showingRenameAlert = false
    @State private var folderVideos: [VideoItem] = []
    
    public init(folder: MediaFolder) {
        self.folder = folder
    }
    
    public var body: some View {
        Group {
            let items = storageManager.videos.filter { $0.folderId == folder.id }
            if items.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text("Dieser Ordner ist leer")
                        .font(.headline)
                    Text("Tippe bei einem Video in der Hauptmediathek auf 'In Ordner verschieben', um es hierhin zu sortieren.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        MediaItemRow(
                            item: item,
                            onPlay: {
                                selectedVideoForPlay = item
                            },
                            onShare: {
                                shareURL = item.fileURL
                                showingShareSheet = true
                            },
                            onSaveToPhotos: {
                                Task {
                                    _ = await storageManager.exportToPhotoLibrary(videoItem: item)
                                }
                            },
                            onRename: {
                                videoToRename = item
                                renameText = item.title
                                showingRenameAlert = true
                            },
                            onMoveToFolder: {
                                storageManager.moveVideo(item, toFolder: nil)
                            }
                        )
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let video = items[index]
                            storageManager.deleteVideo(video)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedVideoForPlay) { video in
            CustomVideoPlayerView(videoItem: video)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("Video umbenennen", isPresented: $showingRenameAlert) {
            TextField("Titel", text: $renameText)
            Button("Abbrechen", role: .cancel) {}
            Button("Speichern") {
                if let item = videoToRename, !renameText.isEmpty {
                    storageManager.renameVideo(item, newTitle: renameText)
                }
            }
        }
    }
}
