import Foundation
import FerventioDomain

enum TwitchIRCRecentSnapshotParser {
    static let maximumLineCharacters = 16 * 1024

    static func parse(
        lines: [String],
        channel: ChatChannel,
        limit: Int,
        nowMilliseconds: @Sendable () -> Int64
    ) -> [ChatMessage] {
        guard limit > 0 else {
            return []
        }

        var messagesByID: [String: ChatMessage] = [:]
        for rawLine in lines {
            guard rawLine.count <= maximumLineCharacters,
                  let line = ParsedIRCLine(rawLine) else {
                continue
            }

            switch line.command {
            case "PRIVMSG":
                guard let message = parseMessage(
                    line,
                    channel: channel,
                    nowMilliseconds: nowMilliseconds
                ) else {
                    continue
                }
                messagesByID[message.id] = message

            case "CLEARMSG":
                guard let targetID = line.tags["target-msg-id"]?.nilIfEmpty,
                      let existing = messagesByID[targetID] else {
                    continue
                }
                messagesByID[targetID] = existing.markingDeleted()

            case "CLEARCHAT":
                let targetUserID = line.tags["target-user-id"]?.nilIfEmpty
                let targetLogin = line.trailing?.nilIfEmpty?.lowercased()
                if targetUserID == nil && targetLogin == nil {
                    messagesByID.removeAll(keepingCapacity: true)
                    continue
                }

                for (id, message) in messagesByID {
                    let matchesID = targetUserID.map { message.author.id == $0 } ?? false
                    let matchesLogin = targetLogin.map {
                        message.author.login.caseInsensitiveCompare($0) == .orderedSame
                    } ?? false
                    if matchesID || matchesLogin {
                        messagesByID[id] = message.markingDeleted()
                    }
                }

            default:
                continue
            }
        }

        let sorted = messagesByID.values.sorted { lhs, rhs in
            if lhs.timestampMilliseconds != rhs.timestampMilliseconds {
                return lhs.timestampMilliseconds < rhs.timestampMilliseconds
            }
            return lhs.id < rhs.id
        }
        return Array(sorted.suffix(limit))
    }

    private static func parseMessage(
        _ line: ParsedIRCLine,
        channel: ChatChannel,
        nowMilliseconds: @Sendable () -> Int64
    ) -> ChatMessage? {
        if let rawChannel = line.params.first,
           rawChannel.hasPrefix("#"),
           String(rawChannel.dropFirst()).caseInsensitiveCompare(channel.login) != .orderedSame {
            return nil
        }

        let rawText = line.trailing ?? ""
        let actionPrefix = "\u{1}ACTION "
        let isAction = rawText.hasPrefix(actionPrefix) && rawText.hasSuffix("\u{1}")
        let text: String
        if isAction {
            text = String(rawText.dropFirst(actionPrefix.count).dropLast())
        } else {
            text = rawText
        }
        let actionCodePointOffset = isAction ? actionPrefix.unicodeScalars.count : 0

        let prefixLogin = line.prefix?.split(separator: "!", maxSplits: 1).first.map(String.init)
        let login = line.tags["login"]?.nilIfEmpty
            ?? prefixLogin?.nilIfEmpty
            ?? "unknown"
        let displayName = line.tags["display-name"]?.nilIfEmpty ?? login
        let timestampMilliseconds = line.receivedAtMilliseconds() ?? nowMilliseconds()
        let messageID = line.tags["id"]?.nilIfEmpty
            ?? fallbackMessageID(
                channelID: channel.id,
                timestampMilliseconds: timestampMilliseconds,
                rawText: rawText
            )
        let deleted = line.tags["rm-deleted"] == "1"
        let rewardID = line.tags["custom-reward-id"]?.nilIfEmpty

        let reply = line.tags["reply-parent-msg-id"]?.nilIfEmpty.map { parentID in
            ReplyContext(
                parentMessageID: parentID,
                parentMessageBody: line.tags["reply-parent-msg-body"]?.nilIfEmpty,
                parentUserID: line.tags["reply-parent-user-id"]?.nilIfEmpty,
                parentUserLogin: line.tags["reply-parent-user-login"]?.nilIfEmpty,
                parentUserName: line.tags["reply-parent-display-name"]?.nilIfEmpty,
                threadMessageID: line.tags["reply-thread-parent-msg-id"]?.nilIfEmpty,
                threadUserID: line.tags["reply-thread-parent-user-id"]?.nilIfEmpty,
                threadUserLogin: line.tags["reply-thread-parent-user-login"]?.nilIfEmpty,
                threadUserName: line.tags["reply-thread-parent-display-name"]?.nilIfEmpty
            )
        }

        return ChatMessage(
            id: messageID,
            channelID: channel.id,
            channelLogin: channel.login.lowercased(),
            author: ChatAuthor(
                id: line.tags["user-id"]?.nilIfEmpty ?? "anonymous:\(login.lowercased())",
                login: login,
                displayName: displayName,
                color: line.tags["color"]?.nilIfEmpty,
                badges: parseBadges(line.tags["badges"])
            ),
            text: text,
            fragments: parseFragments(
                text: text,
                emoteTag: line.tags["emotes"],
                codePointOffset: actionCodePointOffset
            ),
            timestamp: iso8601(timestampMilliseconds),
            timestampMilliseconds: timestampMilliseconds,
            reply: reply,
            reward: rewardID.map { ChatReward(id: $0) },
            type: isAction ? .action : (rewardID == nil ? .chat : .reward),
            flags: MessageFlags(
                isDeleted: deleted,
                isAction: isAction,
                isFirstMessage: line.tags["first-msg"] == "1",
                isReturningChatter: line.tags["returning-chatter"] == "1"
            ),
            serverMessageID: messageID
        )
    }

    private static func parseBadges(_ raw: String?) -> [ChatBadge] {
        guard let raw, !raw.isEmpty else {
            return []
        }
        return raw.split(separator: ",").compactMap { entry in
            guard let slash = entry.firstIndex(of: "/"),
                  slash != entry.startIndex,
                  entry.index(after: slash) != entry.endIndex else {
                return nil
            }
            return ChatBadge(
                setID: String(entry[..<slash]),
                id: String(entry[entry.index(after: slash)...])
            )
        }
    }

    private static func parseFragments(
        text: String,
        emoteTag: String?,
        codePointOffset: Int
    ) -> [ChatFragment] {
        guard !text.isEmpty else {
            return [.text("")]
        }
        guard let emoteTag, !emoteTag.isEmpty else {
            return [.text(text)]
        }

        var ranges: [EmoteRange] = []
        for group in emoteTag.split(separator: "/") {
            guard let colon = group.firstIndex(of: ":"), colon != group.startIndex else {
                continue
            }
            let emoteID = String(group[..<colon])
            let rawRanges = group[group.index(after: colon)...]
            for rawRange in rawRanges.split(separator: ",") {
                guard let dash = rawRange.firstIndex(of: "-"), dash != rawRange.startIndex,
                      let rawStart = Int(rawRange[..<dash]),
                      let rawEnd = Int(rawRange[rawRange.index(after: dash)...]) else {
                    continue
                }
                let start = rawStart - codePointOffset
                let endInclusive = rawEnd - codePointOffset
                guard start >= 0, endInclusive >= start else {
                    continue
                }
                ranges.append(
                    EmoteRange(
                        emoteID: emoteID,
                        startCodePoint: start,
                        endCodePointInclusive: endInclusive
                    )
                )
            }
        }
        ranges.sort {
            if $0.startCodePoint != $1.startCodePoint {
                return $0.startCodePoint < $1.startCodePoint
            }
            return $0.endCodePointInclusive < $1.endCodePointInclusive
        }

        guard !ranges.isEmpty else {
            return [.text(text)]
        }

        let scalars = Array(text.unicodeScalars)
        var fragments: [ChatFragment] = []
        var cursor = 0
        for range in ranges {
            guard range.startCodePoint >= cursor,
                  range.endCodePointInclusive < scalars.count else {
                continue
            }
            if range.startCodePoint > cursor {
                fragments.append(.text(string(from: scalars, range: cursor..<range.startCodePoint)))
            }
            let endExclusive = range.endCodePointInclusive + 1
            fragments.append(
                .twitchEmote(
                    text: string(from: scalars, range: range.startCodePoint..<endExclusive),
                    emoteID: range.emoteID,
                    emoteSetID: nil,
                    ownerID: nil,
                    formats: []
                )
            )
            cursor = endExclusive
        }
        if cursor < scalars.count {
            fragments.append(.text(string(from: scalars, range: cursor..<scalars.count)))
        }
        return fragments.isEmpty ? [.text(text)] : fragments
    }

    private static func string(
        from scalars: [Unicode.Scalar],
        range: Range<Int>
    ) -> String {
        var result = ""
        result.unicodeScalars.append(contentsOf: scalars[range])
        return result
    }

    private static func iso8601(_ milliseconds: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(
            from: Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
        )
    }

    private static func fallbackMessageID(
        channelID: String,
        timestampMilliseconds: Int64,
        rawText: String
    ) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in rawText.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "irc:\(channelID):\(timestampMilliseconds):\(String(hash, radix: 16))"
    }

    private struct EmoteRange {
        let emoteID: String
        let startCodePoint: Int
        let endCodePointInclusive: Int
    }
}

private struct ParsedIRCLine {
    let tags: [String: String]
    let prefix: String?
    let command: String
    let params: [String]
    let trailing: String?

    init?(_ rawLine: String) {
        var rest = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r\n"))
        guard !rest.isEmpty else {
            return nil
        }

        var parsedTags: [String: String] = [:]
        if rest.hasPrefix("@") {
            guard let space = rest.firstIndex(of: " "), space != rest.startIndex else {
                return nil
            }
            let tagText = rest[rest.index(after: rest.startIndex)..<space]
            for entry in tagText.split(separator: ";", omittingEmptySubsequences: false) {
                if let equals = entry.firstIndex(of: "=") {
                    let key = String(entry[..<equals])
                    let value = String(entry[entry.index(after: equals)...])
                    parsedTags[key] = Self.unescapeTag(value)
                } else {
                    parsedTags[String(entry)] = ""
                }
            }
            rest = String(rest[rest.index(after: space)...])
        }

        var parsedPrefix: String?
        if rest.hasPrefix(":") {
            guard let space = rest.firstIndex(of: " "), space != rest.startIndex else {
                return nil
            }
            parsedPrefix = String(rest[rest.index(after: rest.startIndex)..<space])
            rest = String(rest[rest.index(after: space)...])
        }

        let parsedCommand: String
        if let space = rest.firstIndex(of: " ") {
            parsedCommand = String(rest[..<space]).uppercased()
            rest = String(rest[rest.index(after: space)...])
        } else {
            parsedCommand = rest.uppercased()
            rest = ""
        }
        guard !parsedCommand.isEmpty else {
            return nil
        }

        var parsedParams: [String] = []
        var parsedTrailing: String?
        while !rest.isEmpty {
            if rest.hasPrefix(":") {
                parsedTrailing = String(rest.dropFirst())
                break
            }
            if let space = rest.firstIndex(of: " ") {
                parsedParams.append(String(rest[..<space]))
                rest = String(rest[rest.index(after: space)...]).droppingLeadingSpaces()
            } else {
                parsedParams.append(rest)
                rest = ""
            }
        }

        tags = parsedTags
        prefix = parsedPrefix
        command = parsedCommand
        params = parsedParams
        trailing = parsedTrailing
    }

    func receivedAtMilliseconds() -> Int64? {
        if let value = tags["tmi-sent-ts"], let parsed = Int64(value) {
            return parsed
        }
        if let value = tags["rm-received-ts"], let parsed = Int64(value) {
            return parsed
        }
        return nil
    }

    private static func unescapeTag(_ value: String) -> String {
        var output = ""
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "\\" else {
                output.append(value[index])
                index = value.index(after: index)
                continue
            }
            let next = value.index(after: index)
            guard next < value.endIndex else {
                output.append("\\")
                break
            }
            switch value[next] {
            case "s": output.append(" ")
            case ":": output.append(";")
            case "\\": output.append("\\")
            case "r": output.append("\r")
            case "n": output.append("\n")
            default: output.append(value[next])
            }
            index = value.index(after: next)
        }
        return output
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func droppingLeadingSpaces() -> String {
        String(drop(while: { $0 == " " }))
    }
}

private extension ChatMessage {
    func markingDeleted() -> ChatMessage {
        ChatMessage(
            id: id,
            eventSubMessageID: eventSubMessageID,
            channelID: channelID,
            channelLogin: channelLogin,
            author: author,
            text: text,
            fragments: fragments,
            timestamp: timestamp,
            timestampMilliseconds: timestampMilliseconds,
            reply: reply,
            reward: reward,
            type: type,
            flags: MessageFlags(
                isDeleted: true,
                isSystem: flags.isSystem,
                isAction: flags.isAction,
                isFirstMessage: flags.isFirstMessage,
                isReturningChatter: flags.isReturningChatter
            ),
            outgoingState: outgoingState,
            outgoingError: outgoingError,
            clientNonce: clientNonce,
            serverMessageID: serverMessageID
        )
    }
}
