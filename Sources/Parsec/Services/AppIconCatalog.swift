import AppKit

struct AppIconOption: Identifiable {
    let id: String
    let title: String
    let image: NSImage
}

@MainActor
enum AppIconCatalog {
    static let defaultID = AppIconConstants.defaultID
    private static let folderName = "AppIcons"
    private static let defaultTitle = "Parsec"
    private static let defaultResourceName = "AppIcon"
    private static let fileExtensions: Set<String> = ["png", "icns"]

    static var options: [AppIconOption] {
        [defaultOption] + bundledOptions
    }

    static func applySelected() {
        let selectedID = BrowserStore.shared.settings.appIconID
        NSApp.applicationIconImage = options.first { $0.id == selectedID && $0.id != defaultID }?.image
    }

    private static var defaultOption: AppIconOption {
        let image = Bundle.main.image(forResource: defaultResourceName) ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
        return AppIconOption(id: defaultID, title: defaultTitle, image: image)
    }

    private static var bundledOptions: [AppIconOption] {
        let urls = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: folderName) ?? []
        return urls
            .filter { fileExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                let baseName = url.deletingPathExtension().lastPathComponent
                guard let image = NSImage(contentsOf: url) else { return nil }
                return AppIconOption(id: baseName, title: displayTitle(for: baseName), image: image)
            }
    }

    private static func displayTitle(for baseName: String) -> String {
        baseName.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }
}
