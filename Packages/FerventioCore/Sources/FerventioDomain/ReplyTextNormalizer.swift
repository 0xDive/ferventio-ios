import Foundation

public enum ReplyTextNormalizer {
    public struct Result: Equatable, Sendable {
        public let text: String
        public let fragments: [ChatFragment]

        public init(text: String, fragments: [ChatFragment]) {
            self.text = text
            self.fragments = fragments
        }
    }

    public static func normalize(
        text: String,
        fragments: [ChatFragment],
        reply: ReplyContext?
    ) -> Result {
        let prefixLength = removablePrefixLength(text: text, reply: reply)
        guard prefixLength > 0 else {
            return Result(text: text, fragments: fragments)
        }

        let normalizedText = String(text.dropFirst(prefixLength))
        var normalizedFragments = removePrefix(from: fragments, count: prefixLength)
        if normalizedFragments.isEmpty && !normalizedText.isEmpty {
            normalizedFragments = [.text(normalizedText)]
        }
        return Result(text: normalizedText, fragments: normalizedFragments)
    }

    public static func normalizeText(text: String, reply: ReplyContext?) -> String {
        let prefixLength = removablePrefixLength(text: text, reply: reply)
        guard prefixLength > 0 else {
            return text
        }
        return String(text.dropFirst(prefixLength))
    }

    private static func removablePrefixLength(text: String, reply: ReplyContext?) -> Int {
        guard let reply, !text.isEmpty else {
            return 0
        }

        var seen = Set<String>()
        let aliases = [reply.parentUserLogin, reply.parentUserName]
            .compactMap { value -> String? in
                guard var alias = value?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty else {
                    return nil
                }
                if alias.first == "@" {
                    alias.removeFirst()
                }
                guard !alias.isEmpty else {
                    return nil
                }
                let key = alias.lowercased()
                guard seen.insert(key).inserted else {
                    return nil
                }
                return alias
            }
            .sorted { $0.count > $1.count }

        for alias in aliases {
            if let end = prefixEnd(text: text, alias: alias) {
                return end
            }
        }
        return 0
    }

    private static func prefixEnd(text: String, alias: String) -> Int? {
        let mention = "@\(alias)"
        guard text.count >= mention.count,
              String(text.prefix(mention.count)).caseInsensitiveCompare(mention) == .orderedSame else {
            return nil
        }

        let characters = Array(text)
        var index = mention.count
        if index == characters.count {
            return index
        }

        let boundary = characters[index]
        guard isWhitespace(boundary) || boundary == "," || boundary == ":" else {
            return nil
        }
        if boundary == "," || boundary == ":" {
            index += 1
        }
        while index < characters.count && isWhitespace(characters[index]) {
            index += 1
        }
        return index
    }

    private static func removePrefix(from fragments: [ChatFragment], count: Int) -> [ChatFragment] {
        var remaining = count
        var result: [ChatFragment] = []
        result.reserveCapacity(fragments.count)

        for fragment in fragments {
            guard remaining > 0 else {
                result.append(fragment)
                continue
            }
            let length = fragment.text.count
            if remaining >= length {
                remaining -= length
                continue
            }

            let remainingText = String(fragment.text.dropFirst(remaining))
            remaining = 0
            if !remainingText.isEmpty {
                result.append(fragment.replacingText(with: remainingText))
            }
        }
        return result
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
