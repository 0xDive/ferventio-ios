import Foundation

public struct ThirdPartyEmoteDefinition: Codable, Equatable, Sendable, Identifiable {
    public let code: String
    public let emoteID: String
    public let provider: String
    public let animated: Bool
    public let imageURL: String?
    public let zeroWidth: Bool
    public let modifier: Bool
    public let modifierPrefix: Bool
    public let modifierFlags: Int

    public var id: String { "\(provider):\(emoteID)" }

    public init(
        code: String,
        emoteID: String,
        provider: String,
        animated: Bool,
        imageURL: String?,
        zeroWidth: Bool = false,
        modifier: Bool = false,
        modifierPrefix: Bool = false,
        modifierFlags: Int = 0
    ) {
        self.code = code
        self.emoteID = emoteID
        self.provider = provider
        self.animated = animated
        self.imageURL = imageURL
        self.zeroWidth = zeroWidth
        self.modifier = modifier
        self.modifierPrefix = modifierPrefix
        self.modifierFlags = modifierFlags
    }
}

public struct ThirdPartyEmoteCatalog: Equatable, Sendable {
    private let byCode: [String: ThirdPartyEmoteDefinition]

    public init(emotes: [ThirdPartyEmoteDefinition]) {
        var resolved: [String: ThirdPartyEmoteDefinition] = [:]
        for emote in emotes {
            let code = emote.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }
            resolved[code] = emote
        }
        byCode = resolved
    }

    public var isEmpty: Bool { byCode.isEmpty }
    public var count: Int { byCode.count }
    public func emote(for code: String) -> ThirdPartyEmoteDefinition? { byCode[code] }

    public static func merging(
        global: [ThirdPartyEmoteDefinition],
        channel: [ThirdPartyEmoteDefinition]
    ) -> ThirdPartyEmoteCatalog {
        var resolved: [String: ThirdPartyEmoteDefinition] = [:]
        for emote in global where !emote.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolved[emote.code] = emote
        }
        for emote in channel where !emote.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolved[emote.code] = emote
        }
        return ThirdPartyEmoteCatalog(emotes: Array(resolved.values))
    }
}

public enum ThirdPartyEmoteParser {
    public static func apply(
        to fragments: [ChatFragment],
        catalog: ThirdPartyEmoteCatalog
    ) -> [ChatFragment] {
        guard !catalog.isEmpty else { return fragments }
        return fragments.flatMap { fragment in
            guard case let .text(text) = fragment else { return [fragment] }
            return parseTextFragment(text, catalog: catalog)
        }
    }

    private static func parseTextFragment(
        _ text: String,
        catalog: ThirdPartyEmoteCatalog
    ) -> [ChatFragment] {
        guard !text.isEmpty else { return [.text(text)] }

        var result: [ChatFragment] = []
        var current = ""
        var currentIsWhitespace: Bool?

        func flush() {
            guard !current.isEmpty else { return }
            if currentIsWhitespace == false,
               let emote = catalog.emote(for: current) {
                let provider = emote.modifier && emote.provider.caseInsensitiveCompare("ffz") == .orderedSame
                    ? FfzModifierFragmentMetadata.providerMarker(
                        prefix: emote.modifierPrefix,
                        flags: emote.modifierFlags
                    )
                    : emote.provider
                result.append(
                    .thirdPartyEmote(
                        text: current,
                        emoteID: emote.emoteID,
                        provider: provider,
                        animated: emote.animated,
                        imageURL: emote.imageURL,
                        zeroWidth: emote.zeroWidth
                    )
                )
            } else {
                result.append(.text(current))
            }
            current.removeAll(keepingCapacity: true)
        }

        for character in text {
            let isWhitespace = character.isWhitespace
            if let currentIsWhitespace, currentIsWhitespace != isWhitespace { flush() }
            currentIsWhitespace = isWhitespace
            current.append(character)
        }
        flush()
        return result
    }
}

public enum FfzModifierFragmentMetadata {
    private static let prefix = "ffz-modifier:"

    public static func providerMarker(prefix isPrefix: Bool, flags: Int) -> String {
        "\(prefix)\(isPrefix ? "prefix" : "suffix"):\(max(0, flags))"
    }

    public static func parse(provider: String) -> (prefix: Bool, flags: Int)? {
        guard provider.hasPrefix(prefix) else { return nil }
        let payload = provider.dropFirst(prefix.count)
        let parts = payload.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let flags = Int(parts[1]),
              flags >= 0 else { return nil }
        switch parts[0] {
        case "prefix": return (true, flags)
        case "suffix": return (false, flags)
        default: return nil
        }
    }
}
