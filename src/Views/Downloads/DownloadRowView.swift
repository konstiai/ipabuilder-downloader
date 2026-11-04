import SwiftUI

public struct DownloadRowView: View {
    public let item: DownloadTaskItem
    @ObservedObject var downloadManager = DownloadManager.shared
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Icon für Status / Typ
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(item.quality.badgeColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: item.quality.iconName)
                        .font(.title3)
                        .foregroundStyle(item.quality.badgeColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(item.quality.shortLabel)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.quality.badgeColor.opacity(0.2))
                            .foregroundStyle(item.quality.badgeColor)
                            .clipShape(Capsule())
                        
                        Text(item.status.label)
                            .font(.caption2)
                            .foregroundStyle(item.status.color)
                    }
                }
                
                Spacer()
                
                // Steuerungs-Buttons (Pause/Resume/Cancel/Retry)
                HStack(spacing: 8) {
                    if item.status == .downloading {
                        Button {
                            downloadManager.pauseDownload(itemId: item.id)
                        } label: {
                            Image(systemName: "pause.fill")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                                .frame(width: 32, height: 32)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(Circle())
                        }
                    } else if item.status == .paused {
                        Button {
                            downloadManager.resumeDownload(itemId: item.id)
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.subheadline)
                                .foregroundStyle(.blue)
                                .frame(width: 32, height: 32)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(Circle())
                        }
                    } else if case .failed = item.status {
                        Button {
                            downloadManager.retryDownload(itemId: item.id)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .frame(width: 32, height: 32)
                                .background(Color.red.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    
                    if item.status != .completed {
                        Button {
                            downloadManager.cancelDownload(itemId: item.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Color(uiColor: .tertiarySystemFill))
                                .clipShape(Circle())
                        }
                    }
                }
            }
            
            // Fortschrittsbalken
            if item.status == .downloading || item.status == .paused {
                VStack(spacing: 4) {
                    ProgressView(value: item.progress)
                        .progressViewStyle(.linear)
                        .tint(item.status == .paused ? .orange : .blue)
                    
                    HStack {
                        Text("\(Int(item.progress * 100))%")
                            .font(.caption2.bold())
                        
                        Spacer()
                        
                        if item.totalBytes > 0 {
                            Text("\(Formatters.formatBytes(item.downloadedBytes)) von \(Formatters.formatBytes(item.totalBytes))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(Formatters.formatBytes(item.downloadedBytes))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        if item.status == .downloading && item.speedBytesPerSecond > 0 {
                            Text("• \(Formatters.formatSpeed(item.speedBytesPerSecond))")
                                .font(.caption2.bold())
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
