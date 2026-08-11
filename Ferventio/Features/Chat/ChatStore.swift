import Foundation
import FerventioDomain
import FerventioNetworking
import Observation

protocol EventSubChatStreaming: Sendable {
    func connect(channel: ChatChannel, lease: TwitchAccessLease) async throws -> EventSubSubscription
    func nextEvent() async throws -> TwitchEventSubChatClient.Event
    func disconnect() async
}

extension TwitchEventSubChatClient: EventSubChatStreaming {}

protocol ChatMessageSending: Sendable {
    func sendMessage(
        clientID: String,
        accessToken: String,
        broadcasterID: String,
        senderID: String,
        message: String,
        replyParentMessageID: String?
    ) async throws -> ChatSendResult
}

extension TwitchChatAPIClient: ChatMessageSending {}

@MainActor
@Observable
final class ChatStore {
    enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case failed
    }

    static let maximumMessages = 2_000
    static let maximumMessageCharacters = 500

    var channelInput = ""
    var composerText = ""
    private(set) var channel: ChatChannel?
    private(set) var messages: [ChatMessage] = []
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var isSending = false
    private(set) var replyTarget: ChatMessage?
    var showsConnectionError = false
    var showsSendError = false

    var canSend: Bool {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        return connectionState == .connected
            && !isSending
            && !text.isEmpty
            && composerText.count <= Self.maximumMessageCharacters
    }

    @ObservationIgnored private let client: any EventSubChatStreaming
    @ObservationIgnored private let sender: any ChatMessageSending
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activeLease: TwitchAccessLease?
    @ObservationIgnored private var localAuthor: ChatAuthor?

    init(
        client: (any EventSubChatStreaming)? = nil,
        sender: (any ChatMessageSending)? = nil
    ) {
        self.client = client ?? TwitchEventSubChatClient()
        self.sender = sender ?? TwitchChatAPIClient()
    }

    func prepareDefaultChannel(login: String) {
        if channelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            channelInput = login
        }
    }

    func connect(
        channel: ChatChannel,
        lease: TwitchAccessLease,
        currentUser: TwitchUser?
    ) async {
        generation &+= 1
        let currentGeneration = generation
        receiveTask?.cancel()
        receiveTask = nil
        await client.disconnect()

        self.channel = channel
        activeLease = lease
        localAuthor = ChatAuthor(
            id: lease.session.userID,
            login: lease.session.login,
            displayName: currentUser?.displayName ?? lease.session.login,
            profileImageURL: currentUser?.profileImageURL
        )
        messages.removeAll(keepingCapacity: true)
        replyTarget = nil
        connectionState = .connecting
        showsConnectionError = false
        showsSendError = false

        do {
            _ = try await client.connect(channel: channel, lease: lease)
            guard generation == currentGeneration else {
                return
            }
            connectionState = .connected
            startReceiving(generation: currentGeneration)
        } catch {
            guard generation == currentGeneration else {
                return
            }
            connectionState = .failed
            showsConnectionError = true
        }
    }

    func failChannelResolution() {
        connectionState = .failed
        showsConnectionError = true
    }

    func disconnect() async {
        generation &+= 1
        receiveTask?.cancel()
        receiveTask = nil
        await client.disconnect()
        channel = nil
        activeLease = nil
        localAuthor = nil
        messages.removeAll(keepingCapacity: false)
        composerText = ""
        replyTarget = nil
        isSending = false
        connectionState = .disconnected
    }

    func beginReply(to message: ChatMessage) {
        guard replyParentID(for: message) != nil,
              message.outgoingState != .sending,
              message.outgoingState != .failed else {
            return
        }
        replyTarget = message
    }

    func cancelReply() {
        replyTarget = nil
    }

    func sendCurrentMessage() async {
        guard canSend,
              let channel,
              let lease = activeLease,
              let author = localAuthor else {
            return
        }

        let text = composerText
        let selectedReply = replyTarget
        let replyParentMessageID = selectedReply.flatMap { replyParentID(for: $0) }
        let nonce = UUID().uuidString.lowercased()
        let now = Date()
        let localMessage = ChatMessage(
            id: "local-\(nonce)",
            channelID: channel.id,
            channelLogin: channel.login,
            author: author,
            text: text,
            timestamp: ISO8601DateFormatter().string(from: now),
            timestampMilliseconds: Int64((now.timeIntervalSince1970 * 1_000).rounded(.towardZero)),
            reply: makeLocalReplyContext(message: selectedReply, parentID: replyParentMessageID),
            outgoingState: .sending,
            clientNonce: nonce
        )

        composerText = ""
        replyTarget = nil
        isSending = true
        showsSendError = false
        messages.append(localMessage)
        trimMessagesIfNeeded()
        defer { isSending = false }

        do {
            let result = try await sender.sendMessage(
                clientID: lease.session.clientID,
                accessToken: lease.accessToken,
                broadcasterID: channel.id,
                senderID: lease.session.userID,
                message: text,
                replyParentMessageID: replyParentMessageID
            )
            guard result.isSent, let serverMessageID = result.messageID else {
                markOptimisticMessage(
                    nonce: nonce,
                    state: .failed,
                    serverMessageID: nil,
                    error: result.dropReason?.message ?? result.dropReason?.code
                )
                showsSendError = true
                return
            }
            reconcileOptimisticMessage(nonce: nonce, serverMessageID: serverMessageID)
        } catch {
            markOptimisticMessage(
                nonce: nonce,
                state: .failed,
                serverMessageID: nil,
                error: String(describing: error)
            )
            showsSendError = true
        }
    }

    private func startReceiving(generation currentGeneration: Int) {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.generation == currentGeneration {
                do {
                    let event = try await self.client.nextEvent()
                    guard self.generation == currentGeneration else {
                        return
                    }
                    self.apply(event)
                } catch is CancellationError {
                    return
                } catch {
                    guard self.generation == currentGeneration else {
                        return
                    }
                    self.connectionState = .failed
                    self.showsConnectionError = true
                    return
                }
            }
        }
    }

    func apply(_ event: TwitchEventSubChatClient.Event) {
        switch event {
        case let .message(message):
            if connectionState == .reconnecting {
                connectionState = .connected
            }
            applyServerMessage(message)

        case .reconnected:
            connectionState = .connected

        case .revocation:
            connectionState = .failed
            showsConnectionError = true
        }
    }

    private func applyServerMessage(_ message: ChatMessage) {
        if let optimisticIndex = messages.firstIndex(where: { $0.serverMessageID == message.id }) {
            messages[optimisticIndex] = message
            return
        }
        if let existingIndex = messages.firstIndex(where: { $0.id == message.id }) {
            messages[existingIndex] = message
            return
        }
        messages.append(message)
        trimMessagesIfNeeded()
    }

    private func reconcileOptimisticMessage(nonce: String, serverMessageID: String) {
        guard let optimisticIndex = messages.firstIndex(where: { $0.clientNonce == nonce }) else {
            return
        }
        if let serverIndex = messages.firstIndex(where: { $0.id == serverMessageID }),
           serverIndex != optimisticIndex {
            messages.remove(at: optimisticIndex)
            return
        }
        messages[optimisticIndex] = replacingOutgoingState(
            messages[optimisticIndex],
            state: .sent,
            serverMessageID: serverMessageID,
            error: nil
        )
    }

    private func markOptimisticMessage(
        nonce: String,
        state: OutgoingMessageState,
        serverMessageID: String?,
        error: String?
    ) {
        guard let index = messages.firstIndex(where: { $0.clientNonce == nonce }) else {
            return
        }
        messages[index] = replacingOutgoingState(
            messages[index],
            state: state,
            serverMessageID: serverMessageID,
            error: error
        )
    }

    private func replyParentID(for message: ChatMessage) -> String? {
        if let serverMessageID = message.serverMessageID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !serverMessageID.isEmpty {
            return serverMessageID
        }
        let id = message.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !id.hasPrefix("local-") else {
            return nil
        }
        return id
    }

    private func makeLocalReplyContext(
        message: ChatMessage?,
        parentID: String?
    ) -> ReplyContext? {
        guard let message, let parentID else {
            return nil
        }
        return ReplyContext(
            parentMessageID: parentID,
            parentMessageBody: message.text,
            parentUserID: message.author.id,
            parentUserLogin: message.author.login,
            parentUserName: message.author.displayName
        )
    }

    private func replacingOutgoingState(
        _ message: ChatMessage,
        state: OutgoingMessageState,
        serverMessageID: String?,
        error: String?
    ) -> ChatMessage {
        ChatMessage(
            id: message.id,
            eventSubMessageID: message.eventSubMessageID,
            channelID: message.channelID,
            channelLogin: message.channelLogin,
            author: message.author,
            text: message.text,
            fragments: message.fragments,
            timestamp: message.timestamp,
            timestampMilliseconds: message.timestampMilliseconds,
            reply: message.reply,
            reward: message.reward,
            type: message.type,
            flags: message.flags,
            outgoingState: state,
            outgoingError: error,
            clientNonce: message.clientNonce,
            serverMessageID: serverMessageID
        )
    }

    private func trimMessagesIfNeeded() {
        let overflow = messages.count - Self.maximumMessages
        if overflow > 0 {
            messages.removeFirst(overflow)
        }
    }
}
