import SwiftUI

public enum MediaFilter: String, CaseIterable, Identifiable {
    case all = "Alle"
    case videos = "Videos"
    case audio = "Audio"
    case favorites = "Favoriten"
    
    public var id: String { rawValue }
}

public enum MediaSort: String, CaseIterable, Identifiable {
    case dateDesc = "Neueste zuerst"
    case dateAsc = "Älteste zuerst"
    case nameAsc = "Name (A-Z)"
    case sizeDesc = "Größte zuerst"
    
    public var id: String { rawValue }
}

public struct LibraryView: View {
    @ObservedObject var storageManager = StorageManager.shared
    
    @State private var searchText = ""
    @State private var selectedFilter: MediaFilter = .all
    @State private var selectedSort: MediaSort = .dateDesc
    
    @State private var selectedVideoForPlay: VideoItem?
    @State private var shareURL: URL?
    @State private var showingShareSheet = false
    
    @State private var videoToRename: VideoItem?
    @State private var renameText = ""
    @State private var showingRenameAlert = false
    
    @State private var videoToMove: VideoItem?
    @State private var showingMoveSheet = false
    
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    
    @State private var saveMessage: String?
    @State private var showingSaveAlert = false
    
    public init() {}
    
    private var filteredVideos: [VideoItem] {
        var result = storageManager.videos
        
        // Filter
        switch selectedFilter {
        case .all:
            break
        case .videos:
            result = result.filter { !$0.isAudioOnly }
        case .audio:
            result = result.filter { $0.isAudioOnly }
        case .favorites:
            result = result.filter { $0.isFavorite }
        }
        
        // Suche
        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Sortierung
        switch selectedSort {
        case .dateDesc:
            result.sort { $0.createdAt > $1.createdAt }
        case .dateAsc:
            result.sort { $0.createdAt < $1.createdAt }
        case .nameAsc:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .sizeDesc:
            result.sort { $0.fileSize > $1.fileSize }
        }
        
        return result
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Ordner-Leiste (Horizontal scrollbar)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button {
                            showingNewFolderAlert = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.plus")
                                Text("Neuer Ordner")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                        }
                        
                        ForEach(storageManager.folders) { folder in
                            NavigationLink {
                                FolderDetailView(folder: folder)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(Color.blue)
                                    Text(folder.name)
                                        .foregroundStyle(.primary)
                                    let count = storageManager.videos.filter { $0.folderId == folder.id }.count
                                    Text("\(count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.2))
                                        .clipShape(Capsule())
                                }
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(uiColor: .tertiarySystemFill))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(AppTheme.cardBackground)
                
                // Filter Segmented Picker
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(MediaFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 6)
                
                // Hauptliste
                if filteredVideos.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "film")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                        Text(searchText.isEmpty ? "Keine Videos vorhanden" : "Keine Ergebnisse für '\(searchText)'")
                            .font(.headline)
                        Text("Heruntergeladene Videos und Audiospuren werden hier automatisch gespeichert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredVideos) { video in
                            MediaItemRow(
                                item: video,
                                onPlay: {
                                    selectedVideoForPlay = video
                                },
                                onShare: {
                                    shareURL = video.fileURL
                                    showingShareSheet = true
                                },
                                onSaveToPhotos: {
                                    saveVideoToPhotos(video)
                                },
                                onRename: {
                                    videoToRename = video
                                    renameText = video.title
                                    showingRenameAlert = true
                                },
                                onMoveToFolder: {
                                    videoToMove = video
                                    showingMoveSheet = true
                                }
                            )
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let video = filteredVideos[index]
                                storageManager.deleteVideo(video)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Mediathek (\(storageManager.videos.count))")
            .searchable(text: $searchText, prompt: "Videos durchsuchen...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sortieren nach", selection: $selectedSort) {
                            ForEach(MediaSort.allCases) { sort in
                                Text(sort.rawValue).tag(sort)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
            .fullScreenCover(item: $selectedVideoForPlay) { video in
                CustomVideoPlayerView(videoItem: video)
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = shareURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .sheet(isPresented: $showingMoveSheet) {
                NavigationStack {
                    List {
                        Button {
                            if let v = videoToMove {
                                storageManager.moveVideo(v, toFolder: nil)
                            }
                            showingMoveSheet = false
                        } label: {
                            HStack {
                                Image(systemName: "tray")
                                Text("Hauptmediathek (Kein Ordner)")
                            }
                        }
                        
                        ForEach(storageManager.folders) { folder in
                            Button {
                                if let v = videoToMove {
                                    storageManager.moveVideo(v, toFolder: folder.id)
                                }
                                showingMoveSheet = false
                            } label: {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(Color.blue)
                                    Text(folder.name)
                                }
                            }
                        }
                    }
                    .navigationTitle("In Ordner verschieben")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { showingMoveSheet = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .alert("Neuer Ordner", isPresented: $showingNewFolderAlert) {
                TextField("Ordnername", text: $newFolderName)
                Button("Abbrechen", role: .cancel) {}
                Button("Erstellen") {
                    let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        storageManager.createFolder(name: trimmed)
                        newFolderName = ""
                    }
                }
            }
            .alert("Video umbenennen", isPresented: $showingRenameAlert) {
                TextField("Titel", text: $renameText)
                Button("Abbrechen", role: .cancel) {}
                Button("Speichern") {
                    if let v = videoToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                        storageManager.renameVideo(v, newTitle: renameText)
                    }
                }
            }
            .alert("Fotomediathek", isPresented: $showingSaveAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveMessage ?? "")
            }
        }
    }
    
    private func saveVideoToPhotos(_ item: VideoItem) {
        Task {
            let res = await storageManager.exportToPhotoLibrary(videoItem: item)
            await MainActor.run {
                switch res {
                case .success:
                    self.saveMessage = "Erfolgreich in den Aufnahmen gespeichert!"
                    AppTheme.triggerNotificationHaptic(type: .success)
                case .failure(let err):
                    self.saveMessage = "Fehler: \(err.localizedDescription)"
                    AppTheme.triggerNotificationHaptic(type: .error)
                }
                self.showingSaveAlert = true
            }
        }
    }
}
