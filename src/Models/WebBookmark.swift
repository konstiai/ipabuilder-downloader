import Foundation

public struct WebBookmark: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var urlString: String
    public var iconSystemName: String
    public var isDefault: Bool
    
    public init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        iconSystemName: String = "globe",
        isDefault: Bool = false
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.iconSystemName = iconSystemName
        self.isDefault = isDefault
    }
    
    public var url: URL? {
        return URL(string: urlString)
    }
    
    public static var defaults: [WebBookmark] {
        return [
            WebBookmark(title: "YouTube", urlString: "https://m.youtube.com", iconSystemName: "play.rectangle.fill", isDefault: true),
            WebBookmark(title: "TikTok", urlString: "https://www.tiktok.com", iconSystemName: "music.note", isDefault: true),
            WebBookmark(title: "Vimeo", urlString: "https://vimeo.com", iconSystemName: "film.fill", isDefault: true),
            WebBookmark(title: "Dailymotion", urlString: "https://www.dailymotion.com", iconSystemName: "tv.fill", isDefault: true),
            WebBookmark(title: "X / Twitter", urlString: "https://twitter.com", iconSystemName: "bubble.left.and.bubble.right.fill", isDefault: true),
            WebBookmark(title: "Google", urlString: "https://www.google.com", iconSystemName: "magnifyingglass", isDefault: true)
        ]
    }
}

public struct BrowserTab: Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var urlString: String
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isLoading: Bool
    
    public init(
        id: UUID = UUID(),
        title: String = "Neuer Tab",
        urlString: String = "https://www.google.com",
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        isLoading: Bool = false
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
    }
}
