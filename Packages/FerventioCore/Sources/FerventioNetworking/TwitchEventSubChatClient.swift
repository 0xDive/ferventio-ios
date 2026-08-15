import Foundation
import FerventioDomain

public actor TwitchEventSubChatClient {
    public enum Event: Equatable, Sendable {
        case message(ChatMessage)
        case poll(PollOverlay)
        case prediction(PredictionOverlay)
        case reconnected(sessionID: String)
        case revocation(subscriptionType: String, status: String)
    }

    public enum Error: Swift.Error, Equatable {
        case invalidWelcome
        case subscriptionSessionMismatch
        case missingReconnectURL
        case authorizationRevoked
        case reconnectExhausted
    }

    private static let maximumRememberedMessageIDs = 2_048

    private let webSocket: EventSubWebSocketConnection
    private let subscriptions: TwitchEventSubAPIClient
    private var seenMessageIDs = Set<String>()
    private var messageIDOrder: [String] = []
    private var activeChannel: ChatChannel?
    private var activeLease: TwitchAccessLease?

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
        seenMessageIDs.removeAll(keepingCapacity: true)
        messageIDOrder.removeAll(keepingCapacity: true)
        do {
            let established = try await establishFreshConnection(channel: channel, lease: lease)
            activeChannel = channel
            activeLease = lease
            return established.subscription
        } catch {
            activeChannel = nil
            activeLease = nil
            throw error
        }
    }

    public func nextEvent() async throws -> Event {
        do {
            return try await nextEventWithoutTransportRecovery()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as Error where error == .authorizationRevoked {
            throw error
        } catch {
            if isNonRetryable(error) {
                throw error
            }
            return try await reconnectAfterTransportFailure()
        }
    }

    public func disconnect() async {
        await webSocket.close()
        activeChannel = nil
        activeLease = nil
        seenMessageIDs.removeAll(keepingCapacity: false)
        messageIDOrder.removeAll(keepingCapacity: false)
    }

    private func nextEventWithoutTransportRecovery() async throws -> Event {
        while true {
            let envelope = try await webSocket.receive()
            guard EventSubChannelScope.accepts(
                envelope,
                activeChannelID: activeChannel?.id
            ) else {
                continue
            }
            if shouldIgnoreDuplicate(envelope) {
                continue
            }

            switch envelope.messageType {
            case "notification":
                if let message = envelope.chatMessage {
                    return .message(message)
                }
                if let poll = envelope.poll {
                    return .poll(poll)
                }
                if let prediction = envelope.prediction {
                    return .prediction(prediction)
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

    private func reconnectAfterTransportFailure() async throws -> Event {
        guard let channel = activeChannel, let lease = activeLease else {
            throw Error.reconnectExhausted
        }

        for attempt in 0..<ReconnectBackoff.maximumAttempts {
            try Task.checkCancellation()
            let delayMilliseconds = ReconnectBackoff.delayMilliseconds(forAttempt: attempt)
            try await Task.sleep(for: .milliseconds(Int64(delayMilliseconds)))

            do {
                let established = try await establishFreshConnection(channel: channel, lease: lease)
                return .reconnected(sessionID: established.sessionID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if isNonRetryable(error) {
                    throw error
                }
            }
        }

        await webSocket.close()
        throw Error.reconnectExhausted
    }

    private func establishFreshConnection(
        channel: ChatChannel,
        lease: TwitchAccessLease
    ) async throws -> (subscription: EventSubSubscription, sessionID: String) {
        await webSocket.close()
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

            try await subscribeToInteractiveEvents(
                channel: channel,
                lease: lease,
                sessionID: sessionID
            )
            return (subscription, sessionID)
        } catch {
            await webSocket.close()
            throw error
        }
    }

    private func subscribeToInteractiveEvents(
        channel: ChatChannel,
        lease: TwitchAccessLease,
        sessionID: String
    ) async throws {
        for type in InteractiveEventSubSubscriptionType.enabledTypes(for: lease.session.scopes) {
            try Task.checkCancellation()
            do {
                _ = try await subscriptions.createInteractiveSubscription(
                    clientID: lease.session.clientID,
                    accessToken: lease.accessToken,
                    sessionID: sessionID,
                    broadcasterID: channel.id,
                    type: type
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }
    }

    private func isNonRetryable(_ error: Swift.Error) -> Bool {
        if let eventSubError = error as? Error,
           eventSubError == .authorizationRevoked {
            return true
        }
        if let apiError = error as? TwitchEventSubAPIClient.Error,
           case let .httpStatus(status, _) = apiError,
           status == 401 || status == 403 {
            return true
        }
        return false
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
