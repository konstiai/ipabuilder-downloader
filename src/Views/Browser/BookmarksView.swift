import SwiftUI

public struct BookmarksView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var storageManager = StorageManager.shared
    
    public var onSelectBookmark: (String) -> Void
    
    @State private var showingAddSheet = false
    @State private var newBookmarkTitle = ""
    @State private var newBookmarkURL = ""
    
    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Gespeicherte Lesezeichen")) {
                    ForEach(storageManager.bookmarks) { bookmark in
                        Button {
                            onSelectBookmark(bookmark.urlString)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: bookmark.iconSystemName)
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                                    .frame(width: 28)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(bookmark.urlString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { indexSet in
                        storageManager.bookmarks.remove(atOffsets: indexSet)
                        storageManager.saveBookmarks()
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Lesezeichen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    Form {
                        Section(header: Text("Neues Lesezeichen")) {
                            TextField("Name (z.B. YouTube)", text: $newBookmarkTitle)
                            TextField("URL (https://...)", text: $newBookmarkURL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    .navigationTitle("Lesezeichen hinzufügen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abbrechen") { showingAddSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Speichern") {
                                var url = newBookmarkURL.trimmingCharacters(in: .whitespaces)
                                if !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
                                    url = "https://\(url)"
                                }
                                let newB = WebBookmark(title: newBookmarkTitle.isEmpty ? "Lesezeichen" : newBookmarkTitle, urlString: url)
                                storageManager.bookmarks.append(newB)
                                storageManager.saveBookmarks()
                                showingAddSheet = false
                                newBookmarkTitle = ""
                                newBookmarkURL = ""
                            }
                            .disabled(newBookmarkURL.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}
