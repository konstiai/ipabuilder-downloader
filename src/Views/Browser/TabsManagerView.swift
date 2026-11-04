import SwiftUI

public struct TabsManagerView: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding public var tabs: [BrowserTab]
    @Binding public var currentTabIndex: Int
    public var onNewTab: () -> Void
    
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(tab.title)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if tabs.count > 1 {
                                    Button {
                                        closeTab(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            
                            // Tab Snapshot / Preview Box
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(index == currentTabIndex ? Color.blue.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
                                
                                VStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .font(.title)
                                        .foregroundStyle(index == currentTabIndex ? .blue : .secondary)
                                    Text(tab.urlString)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 8)
                                }
                            }
                            .frame(height: 140)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(index == currentTabIndex ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            currentTabIndex = index
                            dismiss()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Tabs (\(tabs.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        onNewTab()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
    
    private func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        if currentTabIndex >= tabs.count {
            currentTabIndex = tabs.count - 1
        }
    }
}
