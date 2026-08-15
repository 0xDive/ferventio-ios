import Foundation
import FerventioDomain

protocol EventSubWebSocketTransport: Sendable {
    func connect(to url: URL) async throws -> EventSubEnvelope
    func receive() async throws -> EventSubEnvelope
    func migrate(to reconnectURL: URL) async throws -> EventSubEnvelope
    func close() async
}

extension EventSubWebSocketConnection: EventSubWebSocketTransport {}

protocol EventSubSubscriptionCreating: Sendable {
    func createChatMessageSubscription(
        clientID: String,
        accessToken: String,
        sessionID: String,
        broadcasterID: String,
        userID: String
    ) async throws -> EventSubSubscription

    func createInteractiveSubscription(
        clientID: String,
        accessToken: String,
        sessionID: String,
        broadcasterID: String,
        type: InteractiveEventSubSubscriptionType
    ) async throws -> EventSubSubscription
}

extension TwitchEventSubAPIClient: EventSubSubscriptionCreating {}

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

    private let webSocket: any EventSubWebSocketTransport
    private let subscriptions: any EventSubSubscriptionCreating
    private var seenMessageIDs = Set<String>()
    private var messageIDOrder: [String] = []
    private var activeChannel: ChatChannel?
    private var activeLease: TwitchAccessLease?
    private var lifecycleGeneration: UInt64 = 0

    public init(
        webSocket: EventSubWebSocketConnection = EventSubWebSocketConnection(),
        subscriptions: TwitchEventSubAPIClient = TwitchEventSubAPIClient()
    ) {
        self.webSocket = webSocket
        self.subscriptions = subscriptions
    }

    init(
        transport: any EventSubWebSocketTransport,
        subscriptionClient: any EventSubSubscriptionCreating
    ) {
        webSocket = transport
        subscriptions = subscriptionClient
    }

    @discardableResult
    public func connect(
        channel: ChatChannel,
        lease: TwitchAccessLease
    ) async throws -> EventSubSubscription {
        lifecycleGeneration &+= 1
        let currentGeneration = lifecycleGeneration
        seenMessageIDs.removeAll(keepingCapacity: true)
        messageIDOrder.removeAll(keepingCapacity: true)
        do {
            let established = try await establishFreshConnection(
                channel: channel,
                lease: lease,
                generation: currentGeneration
            )
            try requireCurrentLifecycle(currentGeneration)
            activeChannel = channel
            activeLease = lease
            return established.subscription
        } catch {
            if lifecycleGeneration == currentGeneration {
                activeChannel = nil
                activeLease = nil
            }
            throw error
        }
    }

    public func nextEvent() async throws -> Event {
        let currentGeneration = lifecycleGeneration
        do {
            return try await nextEventWithoutTransportRecovery(
                generation: currentGeneration
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as Error where error == .authorizationRevoked {
            try requireCurrentLifecycle(currentGeneration)
            throw error
        } catch {
            try requireCurrentLifecycle(currentGeneration)
            if isNonRetryable(error) {
                throw error
            }
            return try await reconnectAfterTransportFailure(
                generation: currentGeneration
            )
        }
    }

    public func disconnect() async {
        lifecycleGeneration &+= 1
        activeChannel = nil
        activeLease = nil
        seenMessageIDs.removeAll(keepingCapacity: false)
        messageIDOrder.removeAll(keepingCapacity: false)
        await webSocket.close()
    }

    private func nextEventWithoutTransportRecovery(
        generation currentGeneration: UInt64
    ) async throws -> Event {
        while true {
            let envelope = try await webSocket.receive()
            try requireCurrentLifecycle(currentGeneration)
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
                try requireCurrentLifecycle(currentGeneration)
                guard let sessionID = welcome.sessionID, !sessionID.isEmpty else {
                    throw Error.invalidWelcome
                }
                return .reconnected(sessionID: sessionID)

            case "revocation":
                let type = envelope.subscriptionType ?? ""
                let status = envelope.revocationStatus ?? ""
                if status == "authorization_revoked" {
                    await webSocket.close()
                    try requireCurrentLifecycle(currentGeneration)
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

    private func reconnectAfterTransportFailure(
        generation currentGeneration: UInt64
    ) async throws -> Event {
        try requireCurrentLifecycle(currentGeneration)
        guard let channel = activeChannel, let lease = activeLease else {
            throw Error.reconnectExhausted
        }

        for attempt in 0..<ReconnectBackoff.maximumAttempts {
            try Task.checkCancellation()
            try requireCurrentLifecycle(currentGeneration)
            let delayMilliseconds = ReconnectBackoff.delayMilliseconds(forAttempt: attempt)
            try await Task.sleep(for: .milliseconds(Int64(delayMilliseconds)))
            try requireCurrentLifecycle(currentGeneration)

            do {
                let established = try await establishFreshConnection(
                    channel: channel,
                    lease: lease,
                    generation: currentGeneration
                )
                try requireCurrentLifecycle(currentGeneration)
                return .reconnected(sessionID: established.sessionID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try requireCurrentLifecycle(currentGeneration)
                if isNonRetryable(error) {
                    throw error
                }
            }
        }

        try requireCurrentLifecycle(currentGeneration)
        await webSocket.close()
        try requireCurrentLifecycle(currentGeneration)
        throw Error.reconnectExhausted
    }

    private func establishFreshConnection(
        channel: ChatChannel,
        lease: TwitchAccessLease,
        generation currentGeneration: UInt64
    ) async throws -> (subscription: EventSubSubscription, sessionID: String) {
        await webSocket.close()
        try requireCurrentLifecycle(currentGeneration)

        do {
            let welcome = try await webSocket.connect(
                to: EventSubWebSocketConnection.defaultURL
            )
            try requireCurrentLifecycle(currentGeneration)
            guard let sessionID = welcome.sessionID, !sessionID.isEmpty else {
                throw Error.invalidWelcome
            }

            let subscription = try await subscriptions.createChatMessageSubscription(
                clientID: lease.session.clientID,
                accessToken: lease.accessToken,
                sessionID: sessionID,
                broadcasterID: channel.id,
                userID: lease.session.userID
            )
            try requireCurrentLifecycle(currentGeneration)
            if let subscriptionSessionID = subscription.sessionID,
               subscriptionSessionID != sessionID {
                throw Error.subscriptionSessionMismatch
            }

            try await subscribeToInteractiveEvents(
                channel: channel,
                lease: lease,
                sessionID: sessionID,
                generation: currentGeneration
            )
            try requireCurrentLifecycle(currentGeneration)
            return (subscription, sessionID)
        } catch {
            if lifecycleGeneration == currentGeneration {
                await webSocket.close()
            }
            throw error
        }
    }

    private func subscribeToInteractiveEvents(
        channel: ChatChannel,
        lease: TwitchAccessLease,
        sessionID: String,
        generation currentGeneration: UInt64
    ) async throws {
        for type in InteractiveEventSubSubscriptionType.enabledTypes(for: lease.session.scopes) {
            try Task.checkCancellation()
            try requireCurrentLifecycle(currentGeneration)
            do {
                _ = try await subscriptions.createInteractiveSubscription(
                    clientID: lease.session.clientID,
                    accessToken: lease.accessToken,
                    sessionID: sessionID,
                    broadcasterID: channel.id,
                    type: type
                )
                try requireCurrentLifecycle(currentGeneration)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try requireCurrentLifecycle(currentGeneration)
                continue
            }
        }
    }

    private func requireCurrentLifecycle(_ expectedGeneration: UInt64) throws {
        guard lifecycleGeneration == expectedGeneration else {
            throw CancellationError()
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
