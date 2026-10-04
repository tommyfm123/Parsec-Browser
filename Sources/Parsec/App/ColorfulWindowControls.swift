import Foundation

enum ColorfulWindowControls {
    private static let aquaColorVariantKey = "AppleAquaColorVariant"
    private static let accentColorKey = "AppleAccentColor"
    private static let graphiteAccentColor = -1
    private static let blueAquaColorVariant = 1
    private static let blueAccentColor = 4

    static func enable() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: accentColorKey) == graphiteAccentColor else { return }
        let argumentDefaults = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let overrides: [String: Any] = [aquaColorVariantKey: blueAquaColorVariant, accentColorKey: blueAccentColor]
        defaults.setVolatileDomain(argumentDefaults.merging(overrides) { current, _ in current }, forName: UserDefaults.argumentDomain)
    }
}
