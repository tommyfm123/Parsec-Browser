import Foundation

enum WebConstants {
    static let wwwPrefix = "www."
    static let httpScheme = "http"
    static let httpsScheme = "https"
    static let aboutBlank = "about:blank"
    static let httpContinueScheme = "parsec-http-continue"
    static let googleSearchURL = "https://www.google.com/search?q="
    static let googleSuggestURL = "https://suggestqueries.google.com/complete/search?client=firefox&q="
    static let faviconPath = "/favicon.ico"
    static let localHosts: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "[::1]"]
    static let localHostSuffixes = [".localhost", ".local", ".test"]
    static let cloudflareChallengeTitle = "Just a moment..."
}

enum StorageConstants {
    static let appFolderName = "Parsec"
    static let stateFileName = "state.json"
    static let historyFileName = "history.sqlite"
    static let faviconFolderName = "Favicons"
    static let arcSidebarRelativePath = "Library/Application Support/Arc/StorableSidebar.json"
    static let easyListResource = "easylist"
    static let easyPrivacyResource = "easyprivacy"
    static let filterListExtension = "txt"
    static let keychainLabelPrefix = "Parsec — "

    static var applicationSupportURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folderURL = baseURL.appending(path: appFolderName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }

    static var arcSidebarURL: URL {
        let realHome = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: realHome).appending(path: arcSidebarRelativePath)
    }
}

enum AppIconConstants {
    static let defaultID = "default"
}

enum LifecycleConstants {
    static let archiveTodayAfter: TimeInterval = 12 * 60 * 60
    static let lifecycleTickInterval: TimeInterval = 60
    static let saveDebounce: Duration = .milliseconds(800)
    static let suggestionDebounce: Duration = .milliseconds(150)
    static let toastDuration: Duration = .milliseconds(1600)
    static let linkPreviewDismissGrace: Duration = .milliseconds(120)
    static let maxSplitPanes = 4
    static let maxRecentlyClosed = 30
    static let commandBarResultLimit = 8
    static let historyResultLimit = 6
}

enum LayoutConstants {
    static let sidebarWidth: CGFloat = 264
    static let hoverEdgeWidth: CGFloat = 8
    static let topBarHeight: CGFloat = 52
    static let conversationTitleLength = 40
    static let trafficLightsHeight: CGFloat = 30
    static let commandBarWidth: CGFloat = 640
    static let peekScale: CGFloat = 0.85
    static let littleWindowSize = CGSize(width: 900, height: 640)
    static let mainWindowSize = CGSize(width: 1400, height: 900)
    static let rowCornerRadius: CGFloat = 8
    static let folderIndent: CGFloat = 14
    static let swipeCommitThreshold: CGFloat = 0.28
    static let newSpaceSwipeDeadZone: CGFloat = 0.44
    static let newSpaceSwipeThreshold: CGFloat = 1.0
}

enum LittleWindowMetrics {
    static let toolbarHeight: CGFloat = 46
    static let contentInset: CGFloat = 8
    static let trafficLightsLeadingInset: CGFloat = 16
    static let trafficLightsReservedWidth: CGFloat = 78
    static let minimumSize = CGSize(width: 520, height: 360)
}

enum SidebarViewMetrics {
    static let outerInset: CGFloat = 8
    static let folderRowHeight: CGFloat = 38
    static let folderIconSize: CGFloat = 19
    static let folderTitleSize: CGFloat = 14
    static let favoriteSpacing: CGFloat = 6
    static let favoriteTileHeight: CGFloat = 44
    static let preferredFavoriteTileWidth: CGFloat = 60
    static let minimumFavoriteColumns = 3

    static func favoriteColumnCount(availableWidth: CGFloat, favoriteCount: Int) -> Int {
        let fittedColumns = Int((max(availableWidth, 0) + favoriteSpacing) / (preferredFavoriteTileWidth + favoriteSpacing))
        return min(max(favoriteCount, 1), max(minimumFavoriteColumns, fittedColumns))
    }

    static func favoriteDropIndex(sourceIndex: Int, targetIndex: Int) -> Int {
        sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
    }

    static func favoriteSlot(at location: CGPoint, availableWidth: CGFloat, columnCount: Int) -> Int {
        let columnWidth = (availableWidth + favoriteSpacing) / CGFloat(columnCount)
        let column = min(max(Int(location.x / columnWidth), 0), columnCount - 1)
        let row = max(Int(location.y / (favoriteTileHeight + favoriteSpacing)), 0)
        return row * columnCount + column
    }

    static func favoriteOrder(_ ids: [UUID], moving sourceID: UUID, to targetIndex: Int) -> [UUID] {
        guard let sourceIndex = ids.firstIndex(of: sourceID) else { return ids }
        var reordered = ids
        reordered.remove(at: sourceIndex)
        reordered.insert(sourceID, at: min(max(targetIndex, 0), reordered.count))
        return reordered
    }
}

enum AssistantPanelMetrics {
    static let width: CGFloat = 390
}
