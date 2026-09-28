import Foundation

struct ArcImportResult {
    let profiles: [Profile]
    let spaces: [Space]
}

@MainActor
enum ArcImporter {
    private typealias JSONObject = [String: Any]
    private static let defaultProfileKey = "default"
    private static let pinnedContainerLabel = "pinned"
    private static let unnamedSpaceTitle = "Space"
    private static let arcFolderIconSymbols = [
        "bulb": "lightbulb.fill",
        "cloud": "cloud.fill",
        "medical": "asterisk",
        "code": "chevron.left.forwardslash.chevron.right",
        "flash": "bolt.fill",
        "skull": "archivebox.fill",
        "construction": "hammer.fill",
        "video": "video.fill",
        "bookmark": "bookmark.fill",
        "musicalNote": "music.note",
        "people": "person.2.fill",
    ]

    static var isAvailable: Bool {
        FileManager.default.isReadableFile(atPath: StorageConstants.arcSidebarURL.path)
    }

    static func importSidebar(from fileURL: URL = StorageConstants.arcSidebarURL) throws -> ArcImportResult {
        let container = try loadSpacesContainer(fileURL: fileURL)
        let items = (container["items"] as? [Any] ?? []).compactMap { $0 as? JSONObject }
        let itemsByID = Dictionary(items.compactMap { item in (item["id"] as? String).map { ($0, item) } }, uniquingKeysWith: { first, _ in first })
        let favoritesRootByProfileKey = Dictionary(
            pairedEntries(container["topAppsContainerIDs"] as? [Any] ?? []).map { (profileKey(from: $0.key), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let arcSpaces = (container["spaces"] as? [Any] ?? []).compactMap { $0 as? JSONObject }
        var profilesByKey: [String: Profile] = [:]
        var orderedProfiles: [Profile] = []
        let spaces = arcSpaces.map { arcSpace in
            let key = profileKey(from: arcSpace["profile"])
            let title = arcSpace["title"] as? String ?? unnamedSpaceTitle
            let profile = profilesByKey[key] ?? {
                let favorites = cleaned(rootChildren(containerID: favoritesRootByProfileKey[key], itemsByID: itemsByID))
                let newProfile = Profile(name: title, favorites: favorites)
                profilesByKey[key] = newProfile
                orderedProfiles.append(newProfile)
                return newProfile
            }()
            let pinnedRootID = pairedEntries(arcSpace["containerIDs"] as? [Any] ?? []).first { $0.key as? String == pinnedContainerLabel }?.id
            return Space(
                title: title,
                profileID: profile.id,
                theme: theme(from: arcSpace) ?? .standard,
                pinned: cleaned(rootChildren(containerID: pinnedRootID, itemsByID: itemsByID))
            )
        }
        return ArcImportResult(profiles: orderedProfiles, spaces: spaces)
    }

    static func folderIconsByTitle() -> [String: String] {
        guard let result = try? importSidebar() else { return [:] }
        let folders = (result.spaces.flatMap(\.pinned) + result.profiles.flatMap(\.favorites)).flatMap(allFolders)
        return Dictionary(folders.compactMap { folder in folder.iconSymbol.map { (folder.title, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    private static func allFolders(in node: SidebarNode) -> [SidebarNode] {
        guard node.isFolder else { return [] }
        return [node] + node.children.flatMap(allFolders)
    }

    static func cleaned(_ nodes: [SidebarNode]) -> [SidebarNode] {
        var seenURLs: Set<URL> = []
        return nodes.compactMap { node in
            node.children = cleaned(node.children)
            guard node.isTab else { return node }
            if node.title == WebConstants.cloudflareChallengeTitle { node.title = node.url?.host() ?? "" }
            guard let url = node.url else { return nil }
            return seenURLs.insert(url).inserted ? node : nil
        }
    }

    private static func loadSpacesContainer(fileURL: URL) throws -> JSONObject {
        let data = try Data(contentsOf: fileURL)
        let root = try JSONSerialization.jsonObject(with: data) as? JSONObject
        let containers = (root?["sidebar"] as? JSONObject)?["containers"] as? [Any] ?? []
        guard let spacesContainer = containers.compactMap({ $0 as? JSONObject }).first(where: { $0["spaces"] != nil }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return spacesContainer
    }

    private static func pairedEntries(_ flatList: [Any]) -> [(key: Any, id: String)] {
        stride(from: 0, to: flatList.count - 1, by: 2).compactMap { index in
            (flatList[index + 1] as? String).map { (flatList[index], $0) }
        }
    }

    private static func profileKey(from profile: Any?) -> String {
        let custom = (profile as? JSONObject)?["custom"] as? JSONObject
        return ((custom?["_0"] as? JSONObject)?["directoryBasename"] as? String) ?? defaultProfileKey
    }

    private static func node(id: String, itemsByID: [String: JSONObject]) -> SidebarNode? {
        guard let item = itemsByID[id], let data = item["data"] as? JSONObject else { return nil }
        let children = (item["childrenIds"] as? [String] ?? []).compactMap { node(id: $0, itemsByID: itemsByID) }
        let itemTitle = item["title"] as? String
        if let tab = data["tab"] as? JSONObject {
            let url = (tab["savedURL"] as? String).flatMap(URL.init(string:))
            return .tab(url: url, title: itemTitle ?? tab["savedTitle"] as? String ?? "")
        }
        if data["splitView"] != nil { return children.isEmpty ? nil : .split(panes: children) }
        if let list = data["list"] as? JSONObject {
            let folder = SidebarNode.folder(title: itemTitle ?? "", children: children)
            let arcIcon = ((list["customInfo"] as? JSONObject)?["iconType"] as? JSONObject)?["icon"] as? String
            folder.iconSymbol = arcIcon.flatMap { arcFolderIconSymbols[$0] }
            return folder
        }
        if data["list"] != nil { return .folder(title: itemTitle ?? "", children: children) }
        return nil
    }

    private static func rootChildren(containerID: String?, itemsByID: [String: JSONObject]) -> [SidebarNode] {
        guard let containerID, let container = itemsByID[containerID] else { return [] }
        return (container["childrenIds"] as? [String] ?? []).compactMap { node(id: $0, itemsByID: itemsByID) }
    }

    private static func theme(from space: JSONObject) -> SpaceTheme? {
        let windowTheme = (space["customInfo"] as? JSONObject)?["windowTheme"] as? JSONObject
        let single = (windowTheme?["background"] as? JSONObject)?["single"] as? JSONObject
        let style = (single?["_0"] as? JSONObject)?["style"] as? JSONObject
        let colorWrapper = (style?["color"] as? JSONObject)?["_0"] as? JSONObject
        let blended = (colorWrapper?["blendedSingleColor"] as? JSONObject)?["_0"] as? JSONObject
        guard let color = blended?["color"] as? JSONObject else { return nil }
        let modifiers = blended?["modifiers"] as? JSONObject ?? [:]
        let noise = modifiers["noiseFactor"] as? Double ?? 0
        let intensity = modifiers["intensityFactor"] as? Double ?? 0
        let themeColor = ThemeColor(
            red: min(color["red"] as? Double ?? 0, 1),
            green: min(color["green"] as? Double ?? 0, 1),
            blue: min(color["blue"] as? Double ?? 0, 1)
        )
        return SpaceTheme(colors: [themeColor], grain: noise * intensity, transparency: SpaceTheme.standard.transparency)
    }
}
