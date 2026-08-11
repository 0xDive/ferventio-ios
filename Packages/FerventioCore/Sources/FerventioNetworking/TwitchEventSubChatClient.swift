import Foundation
import FerventioDomain

public actor TwitchEventSubChatClient {
    public enum Event: Equatable, Sendable {
        case message(ChatMessage)
        case reconnected(sessionID: String)
        case revocation(subscriptionType: String, status: String)
    }

    public enum Error: Swift.Error, Equatable {
        case invalidWelcome
        case subscriptionSessionMismatch
        case missingReconnectURL
        case authorizationRevoked
    }

    private static let maximumRememberedMessageIDs = 2_048

    private let webSocket: EventSubWebSocketConnection
    private let subscriptions: TwitchEventSubAPIClient
    private var seenMessageIDs = Set<String>()
    private var messageIDOrder: [String] = []

    public init(
        webSocket: EventSubWebSocketConnection = EventSubWebSocketConnection(),
        subscriptions: TwitchEventSubAPIClient = TwitchEventSubAPIClient()
    ) {
        self.webSocket = webSocket
        self.subscriptions = subscriptions
    }

    @discardableResult
    public func connect(
        channel: ChatChannel,
        lease: TwitchAccessLease
    ) async throws -> EventSubSubscription {
        await webSocket.close()
        seenMessageIDs.removeAll(keepingCapacity: true)
        messageIDOrder.removeAll(keepingCapacity: true)

        let welcome = try await webSocket.connect()
        guard let sessionID = welcome.sessionID, !sessionID.isEmpty else {
            await webSocket.close()
            throw Error.invalidWelcome
        }

        do {
            let subscription = try await subscriptions.createChatMessageSubscription(
                clientID: lease.session.clientID,
                accessToken: lease.accessToken,
                sessionID: sessionID,
                broadcasterID: channel.id,
                userID: lease.session.userID
            )
            if let subscriptionSessionID = subscription.sessionID,
               subscriptionSessionID != sessionID {
                await webSocket.close()
                throw Error.subscriptionSessionMismatch
            }
            return subscription
        } catch {
            await webSocket.close()
            throw error
        }
    }

    public func nextEvent() async throws -> Event {
        while true {
            let envelope = try await webSocket.receive()
            if shouldIgnoreDuplicate(envelope) {
                continue
            }

            switch envelope.messageType {
            case "notification":
                if let message = envelope.chatMessage {
                    return .message(message)
                }

            case "session_reconnect":
                guard let reconnectURL = envelope.reconnectURL else {
                    throw Error.missingReconnectURL
                }
                let welcome = try await webSocket.migrate(to: reconnectURL)
                guard let sessionID = welcome.sessionID, !sessionID.isEmpty else {
                    throw Error.invalidWelcome
                }
                return .reconnected(sessionID: sessionID)

            case "revocation":
                let type = envelope.subscriptionType ?? ""
                let status = envelope.revocationStatus ?? ""
                if status == "authorization_revoked" {
                    await webSocket.close()
                    throw Error.authorizationRevoked
                }
                return .revocation(subscriptionType: type, status: status)

            case "session_keepalive", "session_welcome":
                continue

            default:
                continue
            }
        }
    }

    public func disconnect() async {
        await webSocket.close()
        seenMessageIDs.removeAll(keepingCapacity: false)
        messageIDOrder.removeAll(keepingCapacity: false)
    }

    private func shouldIgnoreDuplicate(_ envelope: EventSubEnvelope) -> Bool {
        guard envelope.messageType == "notification" || envelope.messageType == "revocation",
              let messageID = envelope.messageID,
              !messageID.isEmpty else {
            return false
        }
        guard seenMessageIDs.insert(messageID).inserted else {
            return true
        }
        messageIDOrder.append(messageID)
        if messageIDOrder.count > Self.maximumRememberedMessageIDs {
            let overflow = messageIDOrder.count - Self.maximumRememberedMessageIDs
            for expiredID in messageIDOrder.prefix(overflow) {
                seenMessageIDs.remove(expiredID)
            }
            messageIDOrder.removeFirst(overflow)
        }
        return false
    }
}
