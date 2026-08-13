import Foundation
import FerventioDomain

public struct EventSubEnvelope: Equatable, Sendable {
    public let messageType: String
    public let messageID: String?
    public let messageTimestamp: String?
    public let sessionID: String?
    public let reconnectURL: URL?
    public let keepaliveTimeoutSeconds: Int?
    public let subscriptionType: String?
    public let revocationStatus: String?
    public let chatMessage: ChatMessage?
    public let poll: PollOverlay?
    public let prediction: PredictionOverlay?

    public init(
        messageType: String,
        messageID: String? = nil,
        messageTimestamp: String? = nil,
        sessionID: String? = nil,
        reconnectURL: URL? = nil,
        keepaliveTimeoutSeconds: Int? = nil,
        subscriptionType: String? = nil,
        revocationStatus: String? = nil,
        chatMessage: ChatMessage? = nil,
        poll: PollOverlay? = nil,
        prediction: PredictionOverlay? = nil
    ) {
        self.messageType = messageType
        self.messageID = messageID
        self.messageTimestamp = messageTimestamp
        self.sessionID = sessionID
        self.reconnectURL = reconnectURL
        self.keepaliveTimeoutSeconds = keepaliveTimeoutSeconds
        self.subscriptionType = subscriptionType
        self.revocationStatus = revocationStatus
        self.chatMessage = chatMessage
        self.poll = poll
        self.prediction = prediction
    }
}

public enum EventSubEnvelopeParser {
    public enum Error: Swift.Error, Equatable {
        case payloadTooLarge
        case invalidJSON
        case missingField(String)
    }

    public static let maximumEnvelopeBytes = 256 * 1_024

    public static func parse(_ raw: String, now: Date = Date()) throws -> EventSubEnvelope {
        guard let data = raw.data(using: .utf8), data.count <= maximumEnvelopeBytes else {
            throw Error.payloadTooLarge
        }
        let rootAny: Any
        do {
            rootAny = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw Error.invalidJSON
        }
        guard let root = rootAny as? [String: Any] else {
            throw Error.invalidJSON
        }

        let metadata = object(root["metadata"])
        let payload = object(root["payload"])
        let messageType = string(metadata["message_type"]) ?? ""
        let messageID = string(metadata["message_id"])
        let timestamp = string(metadata["message_timestamp"])

        switch messageType {
        case "session_welcome", "session_reconnect":
            let session = object(payload["session"])
            return EventSubEnvelope(
                messageType: messageType,
                messageID: messageID,
                messageTimestamp: timestamp,
                sessionID: string(session["id"]),
                reconnectURL: string(session["reconnect_url"]).flatMap(URL.init(string:)),
                keepaliveTimeoutSeconds: integer(session["keepalive_timeout_seconds"])
            )

        case "notification":
            let subscription = object(payload["subscription"])
            let subscriptionType = string(subscription["type"])
            let event = object(payload["event"])
            var chatMessage: ChatMessage?
            var poll: PollOverlay?
            var prediction: PredictionOverlay?

            switch subscriptionType {
            case "channel.chat.message":
                chatMessage = try parseChatMessage(
                    event,
                    timestamp: timestamp ?? "",
                    eventSubMessageID: messageID,
                    now: now
                )

            case "channel.poll.begin", "channel.poll.progress", "channel.poll.end":
                poll = try parsePoll(
                    event,
                    subscriptionType: subscriptionType ?? "",
                    timestamp: timestamp,
                    now: now
                )

            case "channel.prediction.begin", "channel.prediction.progress", "channel.prediction.lock", "channel.prediction.end":
                prediction = try parsePrediction(
                    event,
                    subscriptionType: subscriptionType ?? "",
                    timestamp: timestamp,
                    now: now
                )

            default:
                break
            }

            return EventSubEnvelope(
                messageType: messageType,
                messageID: messageID,
                messageTimestamp: timestamp,
                subscriptionType: subscriptionType,
                chatMessage: chatMessage,
                poll: poll,
                prediction: prediction
            )

        case "revocation":
            let subscription = object(payload["subscription"])
            return EventSubEnvelope(
                messageType: messageType,
                messageID: messageID,
                messageTimestamp: timestamp,
                subscriptionType: string(subscription["type"]) ?? string(metadata["subscription_type"]),
                revocationStatus: string(subscription["status"])
            )

        default:
            return EventSubEnvelope(
                messageType: messageType,
                messageID: messageID,
                messageTimestamp: timestamp
            )
        }
    }

    private static func parseChatMessage(
        _ event: [String: Any],
        timestamp: String,
        eventSubMessageID: String?,
        now: Date
    ) throws -> ChatMessage {
        guard let messageID = nonEmptyString(event["message_id"]) else {
            throw Error.missingField("message_id")
        }
        guard let channelID = nonEmptyString(event["broadcaster_user_id"]) else {
            throw Error.missingField("broadcaster_user_id")
        }
        guard let userID = nonEmptyString(event["chatter_user_id"]) else {
            throw Error.missingField("chatter_user_id")
        }

        let messageObject = object(event["message"])
        let rawText = string(messageObject["text"]) ?? ""
        let reply = parseReply(objectOrNil(event["reply"]))
        let rawFragments = parseFragments(messageObject, fallbackText: rawText)
        let normalized = ReplyTextNormalizer.normalize(
            text: rawText,
            fragments: rawFragments,
            reply: reply
        )
        let rawMessageType = string(event["message_type"]) ?? ""
        let rewardObject = objectOrNil(event["reward"]) ?? objectOrNil(messageObject["reward"])
        let rewardID = string(event["channel_points_custom_reward_id"]) ?? rewardObject.flatMap { string($0["id"]) }
        let reward: ChatReward?
        if rewardID != nil || rewardObject != nil {
            reward = ChatReward(
                id: rewardID,
                title: rewardObject.flatMap { string($0["title"]) },
                cost: rewardObject
                    .flatMap { integer($0["cost"]) ?? integer($0["channel_points"]) }
                    .map(Int64.init)
            )
        } else {
            reward = nil
        }

        let type: ChatMessageType
        if rawMessageType == "action" {
            type = .action
        } else if reward != nil {
            type = .reward
        } else if normalized.fragments.contains(where: { fragment in
            if case .cheermote = fragment { return true }
            return false
        }) {
            type = .cheer
        } else if [
            "channel_points_highlighted",
            "channel_points_sub_only",
            "power_ups_message_effect",
            "power_ups_gigantified_emote",
        ].contains(rawMessageType) {
            type = .reward
        } else if rawMessageType.isEmpty || rawMessageType == "text" || rawMessageType == "user_intro" {
            type = .chat
        } else {
            type = .unknown
        }

        return ChatMessage(
            id: messageID,
            eventSubMessageID: eventSubMessageID,
            channelID: channelID,
            channelLogin: string(event["broadcaster_user_login"]) ?? "",
            author: ChatAuthor(
                id: userID,
                login: string(event["chatter_user_login"]) ?? "",
                displayName: string(event["chatter_user_name"])
                    ?? string(event["chatter_user_login"])
                    ?? "",
                color: string(event["color"]),
                badges: parseBadges(array(event["badges"]))
            ),
            text: normalized.text,
            fragments: normalized.fragments,
            timestamp: timestamp,
            timestampMilliseconds: epochMilliseconds(timestamp, fallback: now),
            reply: reply,
            reward: reward,
            type: type,
            flags: MessageFlags(
                isAction: type == .action,
                isFirstMessage: boolean(event["first_message"]) ?? false,
                isReturningChatter: boolean(event["returning_chatter"]) ?? false
            )
        )
    }

    private static func parsePoll(
        _ event: [String: Any],
        subscriptionType: String,
        timestamp: String?,
        now: Date
    ) throws -> PollOverlay {
        guard let id = nonEmptyString(event["id"]) else {
            throw Error.missingField("id")
        }
        guard let channelID = nonEmptyString(event["broadcaster_user_id"]) else {
            throw Error.missingField("broadcaster_user_id")
        }
        guard let startedAt = nonEmptyString(event["started_at"]) else {
            throw Error.missingField("started_at")
        }

        let choices = array(event["choices"]).compactMap { raw -> PollChoice? in
            guard let choice = raw as? [String: Any],
                  let choiceID = nonEmptyString(choice["id"]) else {
                return nil
            }
            return PollChoice(
                id: choiceID,
                title: string(choice["title"]) ?? "",
                votes: integer(choice["votes"]) ?? 0,
                channelPointsVotes: integer(choice["channel_points_votes"]) ?? 0,
                bitsVotes: integer(choice["bits_votes"]) ?? 0
            )
        }
        let channelPointsVoting = object(event["channel_points_voting"])
        let bitsVoting = object(event["bits_voting"])
        let status: PollStatus = subscriptionType == "channel.poll.end"
            ? PollStatus(twitchValue: string(event["status"]))
            : .active

        return PollOverlay(
            id: id,
            channelID: channelID,
            title: string(event["title"]) ?? "",
            choices: choices,
            status: status,
            startedAtMilliseconds: epochMilliseconds(startedAt, fallback: now),
            endsAtMilliseconds: optionalEpochMilliseconds(string(event["ends_at"])),
            endedAtMilliseconds: optionalEpochMilliseconds(string(event["ended_at"])),
            channelPointsVotingEnabled: boolean(channelPointsVoting["is_enabled"]) ?? false,
            channelPointsPerVote: integer(channelPointsVoting["amount_per_vote"]) ?? 0,
            bitsVotingEnabled: boolean(bitsVoting["is_enabled"]) ?? false,
            bitsPerVote: integer(bitsVoting["amount_per_vote"]) ?? 0,
            updatedAtMilliseconds: epochMilliseconds(timestamp ?? "", fallback: now)
        )
    }

    private static func parsePrediction(
        _ event: [String: Any],
        subscriptionType: String,
        timestamp: String?,
        now: Date
    ) throws -> PredictionOverlay {
        guard let id = nonEmptyString(event["id"]) else {
            throw Error.missingField("id")
        }
        guard let channelID = nonEmptyString(event["broadcaster_user_id"]) else {
            throw Error.missingField("broadcaster_user_id")
        }
        guard let startedAt = nonEmptyString(event["started_at"]) else {
            throw Error.missingField("started_at")
        }

        let outcomes = array(event["outcomes"]).compactMap { raw -> PredictionOutcome? in
            guard let outcome = raw as? [String: Any],
                  let outcomeID = nonEmptyString(outcome["id"]) else {
                return nil
            }
            return PredictionOutcome(
                id: outcomeID,
                title: string(outcome["title"]) ?? "",
                users: integer(outcome["users"]) ?? 0,
                channelPoints: integer64(outcome["channel_points"]) ?? 0,
                color: PredictionOutcomeColor(twitchValue: string(outcome["color"]))
            )
        }

        let status: PredictionStatus
        switch subscriptionType {
        case "channel.prediction.lock":
            status = .locked
        case "channel.prediction.end":
            status = PredictionStatus(twitchValue: string(event["status"]))
        default:
            status = .active
        }

        return PredictionOverlay(
            id: id,
            channelID: channelID,
            title: string(event["title"]) ?? "",
            outcomes: outcomes,
            status: status,
            startedAtMilliseconds: epochMilliseconds(startedAt, fallback: now),
            locksAtMilliseconds: optionalEpochMilliseconds(string(event["locks_at"])),
            lockedAtMilliseconds: optionalEpochMilliseconds(string(event["locked_at"])),
            endedAtMilliseconds: optionalEpochMilliseconds(string(event["ended_at"])),
            winningOutcomeID: nonEmptyString(event["winning_outcome_id"]),
            updatedAtMilliseconds: epochMilliseconds(timestamp ?? "", fallback: now)
        )
    }

    private static func parseReply(_ reply: [String: Any]?) -> ReplyContext? {
        guard let reply,
              let parentMessageID = nonEmptyString(reply["parent_message_id"]) else {
            return nil
        }
        return ReplyContext(
            parentMessageID: parentMessageID,
            parentMessageBody: string(reply["parent_message_body"]),
            parentUserID: string(reply["parent_user_id"]),
            parentUserLogin: string(reply["parent_user_login"]),
            parentUserName: string(reply["parent_user_name"]),
            threadMessageID: string(reply["thread_message_id"]),
            threadUserID: string(reply["thread_user_id"]),
            threadUserLogin: string(reply["thread_user_login"]),
            threadUserName: string(reply["thread_user_name"])
        )
    }

    private static func parseBadges(_ badges: [Any]) -> [ChatBadge] {
        badges.compactMap { raw in
            guard let badge = raw as? [String: Any] else {
                return nil
            }
            return ChatBadge(
                setID: string(badge["set_id"]) ?? "",
                id: string(badge["id"]) ?? "",
                info: string(badge["info"])
            )
        }
    }

    private static func parseFragments(_ message: [String: Any], fallbackText: String) -> [ChatFragment] {
        let fragments = array(message["fragments"]).compactMap { raw -> ChatFragment? in
            guard let fragment = raw as? [String: Any] else {
                return nil
            }
            let type = string(fragment["type"]) ?? ""
            let text = string(fragment["text"]) ?? ""
            switch type {
            case "text":
                return .text(text)

            case "emote":
                let emote = object(fragment["emote"])
                let formats = Set(array(emote["format"]).compactMap { string($0) })
                return .twitchEmote(
                    text: text,
                    emoteID: string(emote["id"]) ?? "",
                    emoteSetID: string(emote["emote_set_id"]),
                    ownerID: string(emote["owner_id"]),
                    formats: formats
                )

            case "mention":
                let mention = object(fragment["mention"])
                return .mention(
                    text: text,
                    userID: string(mention["user_id"]) ?? "",
                    userLogin: string(mention["user_login"]) ?? "",
                    userName: string(mention["user_name"]) ?? ""
                )

            case "cheermote":
                let cheermote = object(fragment["cheermote"])
                return .cheermote(
                    text: text,
                    prefix: string(cheermote["prefix"]) ?? "",
                    bits: integer(cheermote["bits"]) ?? 0,
                    tier: integer(cheermote["tier"]) ?? 0
                )

            case "gif":
                let gif = object(fragment["gif"])
                return .gif(
                    text: text,
                    gifID: string(gif["gif_id"]) ?? "",
                    url: string(gif["url"]) ?? ""
                )

            default:
                return .unknown(text: text, rawType: type.isEmpty ? "unknown" : type)
            }
        }
        return fragments.isEmpty ? [.text(fallbackText)] : fragments
    }

    private static func epochMilliseconds(_ raw: String, fallback: Date) -> Int64 {
        parseDate(raw).map {
            Int64(($0.timeIntervalSince1970 * 1_000).rounded(.towardZero))
        } ?? Int64((fallback.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }

    private static func optionalEpochMilliseconds(_ raw: String?) -> Int64? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let date = parseDate(raw) else {
            return nil
        }
        return Int64((date.timeIntervalSince1970 * 1_000).rounded(.towardZero))
    }

    private static func parseDate(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return fractional.date(from: raw) ?? standard.date(from: raw)
    }

    private static func object(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    private static func objectOrNil(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

    private static func integer64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        if let value = value as? String {
            return Int64(value)
        }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool? {
        value as? Bool
    }
}
