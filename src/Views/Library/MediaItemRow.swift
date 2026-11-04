import SwiftUI

public struct MediaItemRow: View {
    public let item: VideoItem
    @ObservedObject var storageManager = StorageManager.shared
    
    public var onPlay: () -> Void
    public var onShare: () -> Void
    public var onSaveToPhotos: () -> Void
    public var onRename: () -> Void
    public var onMoveToFolder: () -> Void
    
    @State private var thumbnail: UIImage?
    
    public var body: some View {
        HStack(spacing: 14) {
            // Thumbnail mit Duration Badge
            ZStack(alignment: .bottomTrailing) {
                if let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 56)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(item.isAudioOnly ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                            .frame(width: 80, height: 56)
                        
                        Image(systemName: item.isAudioOnly ? "music.note" : "film")
                            .font(.title2)
                            .foregroundStyle(item.isAudioOnly ? .orange : .blue)
                    }
                }
                
                if item.duration > 0 {
                    Text(Formatters.formatDuration(item.duration))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            
            // Titel & Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                
                HStack(spacing: 6) {
                    Text(item.quality.shortLabel)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(item.quality.badgeColor.opacity(0.2))
                        .foregroundStyle(item.quality.badgeColor)
                        .clipShape(Capsule())
                    
                    Text(Formatters.formatBytes(item.fileSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("•")
                        .foregroundStyle(.tertiary)
                    
                    Text(Formatters.formatDate(item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Options-Menü
            Menu {
                Button {
                    onPlay()
                } label: {
                    Label("Abspielen", systemImage: "play.circle")
                }
                
                if !item.isAudioOnly {
                    Button {
                        onSaveToPhotos()
                    } label: {
                        Label("In Aufnahmen speichern", systemImage: "square.and.arrow.down")
                    }
                }
                
                Button {
                    onShare()
                } label: {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                
                Button {
                    storageManager.toggleFavorite(item)
                } label: {
                    Label(item.isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen", systemImage: item.isFavorite ? "star.slash" : "star")
                }
                
                Button {
                    onMoveToFolder()
                } label: {
                    Label("In Ordner verschieben", systemImage: "folder")
                }
                
                Button {
                    onRename()
                } label: {
                    Label("Umbenennen", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    storageManager.deleteVideo(item)
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay()
        }
        .task {
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        if let cached = storageManager.getThumbnailImage(for: item) {
            self.thumbnail = cached
        }
    }
}
