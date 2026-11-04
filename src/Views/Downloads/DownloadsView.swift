import SwiftUI

public struct DownloadsView: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var showingDirectDownload = false
    
    public init() {}
    
    private var activeTasks: [DownloadTaskItem] {
        downloadManager.tasks.filter { $0.status != .completed }
    }
    
    private var completedTasks: [DownloadTaskItem] {
        downloadManager.tasks.filter { $0.status == .completed }
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                if downloadManager.tasks.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                        
                        Text("Keine aktiven Downloads")
                            .font(.title2.bold())
                        
                        Text("Nutze den integrierten Browser oder füge direkt einen Videolink ein, um Downloads in beliebiger Qualität (bis 4K) zu starten.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Button {
                            showingDirectDownload = true
                        } label: {
                            HStack {
                                Image(systemName: "link.badge.plus")
                                Text("Link einfügen")
                            }
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !activeTasks.isEmpty {
                            Section(header: Text("Warteschlange & Aktiv (\(activeTasks.count))")) {
                                ForEach(activeTasks) { task in
                                    DownloadRowView(item: task)
                                }
                            }
                        }
                        
                        if !completedTasks.isEmpty {
                            Section {
                                ForEach(completedTasks) { task in
                                    DownloadRowView(item: task)
                                }
                            } header: {
                                HStack {
                                    Text("Kürzlich fertiggestellt (\(completedTasks.count))")
                                    Spacer()
                                    Button("Bereinigen") {
                                        downloadManager.clearCompleted()
                                    }
                                    .font(.caption)
                                    .textCase(.none)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingDirectDownload = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingDirectDownload) {
                DirectDownloadSheet()
            }
        }
    }
}
