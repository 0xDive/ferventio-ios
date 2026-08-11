import Foundation

public struct ChatBadgeAsset: Codable, Equatable, Sendable, Identifiable {
    public let setID: String
    public let versionID: String
    public let imageURL1x: String?
    public let imageURL2x: String?
    public let imageURL4x: String?
    public let title: String?
    public let description: String?

    public var id: String {
        ChatAssetResolver.badgeAssetKey(setID: setID, versionID: versionID)
    }

    public init(
        setID: String,
        versionID: String,
        imageURL1x: String? = nil,
        imageURL2x: String? = nil,
        imageURL4x: String? = nil,
        title: String? = nil,
        description: String? = nil
    ) {
        self.setID = setID
        self.versionID = versionID
        self.imageURL1x = imageURL1x
        self.imageURL2x = imageURL2x
        self.imageURL4x = imageURL4x
        self.title = title
        self.description = description
    }
}

public enum ChatAssetResolver {
    public enum Theme: String, Sendable {
        case dark
        case light
    }

    public enum TwitchScale: String, Sendable {
        case small = "1.0"
        case medium = "2.0"
        case large = "3.0"
    }

    public static func twitchEmoteURL(
        emoteID: String,
        formats: Set<String>,
        animate: Bool,
        theme: Theme = .dark,
        scale: TwitchScale = .medium
    ) -> URL? {
        let id = emoteID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            return nil
        }
        let format = animate && formats.contains("animated") ? "animated" : "static"
        return URL(
            string: "https://static-cdn.jtvnw.net/emoticons/v2/\(id)/\(format)/\(theme.rawValue)/\(scale.rawValue)"
        )
    }

    public static func twitchEmoteURL(
        fragment: ChatFragment,
        animate: Bool,
        theme: Theme = .dark,
        scale: TwitchScale = .medium
    ) -> URL? {
        guard case let .twitchEmote(_, emoteID, _, _, formats) = fragment else {
            return nil
        }
        return twitchEmoteURL(
            emoteID: emoteID,
            formats: formats,
            animate: animate,
            theme: theme,
            scale: scale
        )
    }

    public static func absoluteImageURL(_ rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("//") {
            return URL(string: "https:\(value)")
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    public static func badgeAssetKey(setID: String, versionID: String) -> String {
        "\(setID.trimmingCharacters(in: .whitespacesAndNewlines)):\(versionID.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    public static func badgeAsset(
        for badge: ChatBadge,
        assets: [String: ChatBadgeAsset]
    ) -> ChatBadgeAsset? {
        assets[badgeAssetKey(setID: badge.setID, versionID: badge.id)]
    }

    public static func preferredBadgeImageURL(_ asset: ChatBadgeAsset) -> URL? {
        absoluteImageURL(asset.imageURL2x)
            ?? absoluteImageURL(asset.imageURL4x)
            ?? absoluteImageURL(asset.imageURL1x)
    }
}
