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
            VStack(spacing: 0) {
                // Prominenter Download-Button immer ganz oben sichtbar
                Button {
                    showingDirectDownload = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Neues Video herunterladen")
                                .font(.headline)
                            Text("Link einfügen • Alle echten Auflösungen (HD/4K)")
                                .font(.caption2)
                                .opacity(0.85)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right.circle")
                            .font(.title3)
                    }
                    .padding()
                    .background(
                        LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .blue.opacity(0.3), radius: 6, x: 0, y: 3)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 6)
                
                Group {
                    if downloadManager.tasks.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)
                            
                            Text("Keine Downloads vorhanden")
                                .font(.title3.bold())
                            
                            Text("Tippe oben auf 'Neues Video herunterladen' oder nutze den internen Browser, um Videos in allen verfügbaren Qualitäten herunterzuladen.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
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
                                        Text("Abgeschlossen (\(completedTasks.count))")
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
