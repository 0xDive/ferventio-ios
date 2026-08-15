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
        case suspended
        case failed
    }

    static let maximumMessages = 2_000
    static let maximumMessageCharacters = 500
    static let remoteRecentMessagesLimit = 100

    var channelInput = ""
    var composerText = ""
    private(set) var channel: ChatChannel?
    private(set) var messages: [ChatMessage] = []
    private(set) var interactiveOverlayState = InteractiveChatOverlayState()
    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var isSending = false
    private(set) var replyTarget: ChatMessage?
    private(set) var historyPreferences: ChatHistoryPreferences
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
    @ObservationIgnored private let history: any ChatHistoryPersisting
    @ObservationIgnored private let recentMessagesLoader: any RecentMessagesLoading
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var recentMessagesTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var sendGeneration = 0
    @ObservationIgnored private var activeLease: TwitchAccessLease?
    @ObservationIgnored private var localAuthor: ChatAuthor?
    @ObservationIgnored private var thirdPartyEmoteCatalog = ThirdPartyEmoteCatalog(emotes: [])

    init(
        client: (any EventSubChatStreaming)? = nil,
        sender: (any ChatMessageSending)? = nil,
        history: (any ChatHistoryPersisting)? = nil,
        recentMessagesLoader: (any RecentMessagesLoading)? = nil,
        historyPreferences: ChatHistoryPreferences = .default
    ) {
        self.client = client ?? TwitchEventSubChatClient()
        self.sender = sender ?? TwitchChatAPIClient()
        self.history = history ?? NoopChatHistory()
        // Tests and reusable stores must never perform external bootstrap I/O
        // unless the production composition explicitly injects the live client.
        self.recentMessagesLoader = recentMessagesLoader ?? NoopRecentMessagesLoader()
        self.historyPreferences = historyPreferences
    }

    func prepareDefaultChannel(login: String) {
        if channelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            channelInput = login
        }
    }

    func updateHistoryPreferences(_ preferences: ChatHistoryPreferences) async {
        let previous = historyPreferences
        historyPreferences = preferences

        if previous.localHistoryEnabled && !preferences.localHistoryEnabled {
            await history.flush()
        }

        if !preferences.recentMessagesEnabled {
            recentMessagesTask?.cancel()
            recentMessagesTask = nil
        } else if !previous.recentMessagesEnabled,
                  connectionState == .connected,
                  let channel {
            startRecentMessagesBootstrap(channel: channel, generation: generation)
        }
    }

    func connect(
        channel: ChatChannel,
        lease: TwitchAccessLease,
        currentUser: TwitchUser?
    ) async {
        generation &+= 1
        sendGeneration &+= 1
        isSending = false
        let currentGeneration = generation
        receiveTask?.cancel()
        receiveTask = nil
        recentMessagesTask?.cancel()
        recentMessagesTask = nil
        await client.disconnect()
        await history.flush()

        self.channel = channel
        interactiveOverlayState = InteractiveChatOverlayState()
        activeLease = lease
        localAuthor = ChatAuthor(
            id: lease.session.userID,
            login: lease.session.login,
            displayName: currentUser?.displayName ?? lease.session.login,
            profileImageURL: currentUser?.profileImageURL
        )
        thirdPartyEmoteCatalog = ThirdPartyEmoteCatalog(emotes: [])
        replyTarget = nil
        connectionState = .connecting
        showsConnectionError = false
        showsSendError = false

        if historyPreferences.localHistoryEnabled {
            let nowMilliseconds = Int64(
                (Date().timeIntervalSince1970 * 1_000).rounded(.towardZero)
            )
            await history.maintain(
                channelID: channel.id,
                retentionBoundaryMilliseconds: historyPreferences
                    .retentionBoundaryMilliseconds(nowMilliseconds: nowMilliseconds),
                keepingLatest: historyPreferences.localHistoryLimit,
                maxDatabaseSizeMB: historyPreferences.maxDatabaseSizeMB
            )
            let restoredMessages = await history.recentMessages(
                channelID: channel.id,
                limit: historyPreferences.initialRestoreLimit
            )
            guard generation == currentGeneration else {
                return
            }
            messages = Array(restoredMessages.suffix(Self.maximumMessages))
        } else {
            messages.removeAll(keepingCapacity: true)
        }

        do {
            _ = try await client.connect(channel: channel, lease: lease)
            guard generation == currentGeneration else {
                return
            }
            connectionState = .connected
            startReceiving(generation: currentGeneration)
            if historyPreferences.recentMessagesEnabled {
                startRecentMessagesBootstrap(
                    channel: channel,
                    generation: currentGeneration
                )
            }
        } catch {
            guard generation == currentGeneration else {
                return
            }
            connectionState = .failed
            showsConnectionError = true
        }
    }

    func failChannelResolution() {
        switch connectionState {
        case .disconnected, .failed:
            connectionState = .failed
        case .connecting, .connected, .reconnecting, .suspended:
            break
        }
        showsConnectionError = true
    }

    func setThirdPartyEmoteCatalog(_ catalog: ThirdPartyEmoteCatalog) {
        thirdPartyEmoteCatalog = catalog
        messages = messages.map(enrich)
    }

    func suspend() async {
        guard channel != nil, activeLease != nil else {
            return
        }
        generation &+= 1
        receiveTask?.cancel()
        receiveTask = nil
        recentMessagesTask?.cancel()
        recentMessagesTask = nil
        await client.disconnect()
        await history.flush()
        connectionState = .suspended
    }

    func resumeIfNeeded() async {
        guard connectionState == .suspended,
              let channel,
              let lease = activeLease else {
            return
        }

        generation &+= 1
        let currentGeneration = generation
        connectionState = .connecting
        showsConnectionError = false

        do {
            _ = try await client.connect(channel: channel, lease: lease)
            guard generation == currentGeneration else {
                return
            }
            connectionState = .connected
            startReceiving(generation: currentGeneration)
            if historyPreferences.recentMessagesEnabled {
                startRecentMessagesBootstrap(
                    channel: channel,
                    generation: currentGeneration
                )
            }
        } catch {
            guard generation == currentGeneration else {
                return
            }
            connectionState = .failed
            showsConnectionError = true
        }
    }

    func disconnect() async {
        generation &+= 1
        sendGeneration &+= 1
        isSending = false
        receiveTask?.cancel()
        receiveTask = nil
        recentMessagesTask?.cancel()
        recentMessagesTask = nil
        await client.disconnect()
        await history.flush()
        channel = nil
        activeLease = nil
        localAuthor = nil
        thirdPartyEmoteCatalog = ThirdPartyEmoteCatalog(emotes: [])
        messages.removeAll(keepingCapacity: false)
        interactiveOverlayState = InteractiveChatOverlayState()
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

    @discardableResult
    func sendCurrentMessage() async -> Bool {
        guard canSend,
              let channel,
              let lease = activeLease,
              let author = localAuthor else {
            return false
        }

        let currentSendGeneration = sendGeneration
        let text = composerText
        let selectedReply = replyTarget
        let replyParentMessageID = selectedReply.flatMap { replyParentID(for: $0) }
        let nonce = UUID().uuidString.lowercased()
        let now = Date()
        let localMessage = enrich(
            ChatMessage(
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
        )

        composerText = ""
        replyTarget = nil
        isSending = true
        showsSendError = false
        messages.append(localMessage)
        trimMessagesIfNeeded()
        defer {
            if sendGeneration == currentSendGeneration {
                isSending = false
            }
        }

        do {
            let result = try await sender.sendMessage(
                clientID: lease.session.clientID,
                accessToken: lease.accessToken,
                broadcasterID: channel.id,
                senderID: lease.session.userID,
                message: text,
                replyParentMessageID: replyParentMessageID
            )
            guard sendGeneration == currentSendGeneration else {
                return false
            }
            guard result.isSent, let serverMessageID = result.messageID else {
                markOptimisticMessage(
                    nonce: nonce,
                    state: .failed,
                    serverMessageID: nil,
                    error: result.dropReason?.message ?? result.dropReason?.code
                )
                showsSendError = true
                return false
            }
            reconcileOptimisticMessage(nonce: nonce, serverMessageID: serverMessageID)
            return true
        } catch {
            guard sendGeneration == currentSendGeneration else {
                return false
            }
            markOptimisticMessage(
                nonce: nonce,
                state: .failed,
                serverMessageID: nil,
                error: String(describing: error)
            )
            showsSendError = true
            return false
        }
    }

    func mergeRecentMessages(_ recent: [ChatMessage]) async {
        guard !recent.isEmpty else {
            return
        }

        let canonicalByID = Dictionary(uniqueKeysWithValues: recent.map { ($0.id, $0) })
        let enrichedRecent = recent.map(enrich)
        let merged = RecentMessagesMerge.merge(
            existing: messages,
            recent: enrichedRecent,
            limit: Self.maximumMessages
        )
        guard !merged.addedMessages.isEmpty else {
            return
        }

        messages = merged.messages
        guard historyPreferences.localHistoryEnabled else {
            return
        }
        for added in merged.addedMessages {
            if let canonical = canonicalByID[added.id] {
                await history.enqueue(canonical)
            }
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
                    if self.historyPreferences.localHistoryEnabled,
                       case let .message(message) = event {
                        await self.history.enqueue(message)
                    }
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

    private func startRecentMessagesBootstrap(
        channel: ChatChannel,
        generation currentGeneration: Int
    ) {
        guard historyPreferences.recentMessagesEnabled else {
            return
        }
        recentMessagesTask?.cancel()
        recentMessagesTask = nil
        recentMessagesTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.recentMessagesLoader.load(
                    channel: channel,
                    limit: Self.remoteRecentMessagesLimit
                )
                guard !Task.isCancelled,
                      self.generation == currentGeneration,
                      self.channel?.id == channel.id,
                      self.historyPreferences.recentMessagesEnabled else {
                    return
                }
                await self.mergeRecentMessages(result.messages)
            } catch is CancellationError {
                return
            } catch {
                // Recent snapshots are an optional bootstrap source. Failure
                // must never affect EventSub connectivity or the local cache.
                return
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

        case let .poll(poll):
            guard poll.channelID == channel?.id else {
                return
            }
            interactiveOverlayState = InteractiveChatOverlayReducer.reduce(
                state: interactiveOverlayState,
                event: .pollSnapshot(poll)
            )

        case let .prediction(prediction):
            guard prediction.channelID == channel?.id else {
                return
            }
            interactiveOverlayState = InteractiveChatOverlayReducer.reduce(
                state: interactiveOverlayState,
                event: .predictionSnapshot(prediction)
            )

        case .reconnected:
            connectionState = .connected

        case let .revocation(subscriptionType, _):
            if subscriptionType == "channel.chat.message" {
                connectionState = .failed
                showsConnectionError = true
            } else if subscriptionType.hasPrefix("channel.poll.")
                        || subscriptionType.hasPrefix("channel.prediction."),
                      let channelID = channel?.id {
                interactiveOverlayState = InteractiveChatOverlayReducer.reduce(
                    state: interactiveOverlayState,
                    event: .clearChannel(channelID)
                )
            }
        }
    }

    private func applyServerMessage(_ message: ChatMessage) {
        let message = enrich(message)
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

    private func enrich(_ message: ChatMessage) -> ChatMessage {
        let fragments = ThirdPartyEmoteParser.apply(
            to: message.fragments,
            catalog: thirdPartyEmoteCatalog
        )
        guard fragments != message.fragments else {
            return message
        }
        return replacingFragments(message, fragments: fragments)
    }

    private func replacingFragments(
        _ message: ChatMessage,
        fragments: [ChatFragment]
    ) -> ChatMessage {
        ChatMessage(
            id: message.id,
            eventSubMessageID: message.eventSubMessageID,
            channelID: message.channelID,
            channelLogin: message.channelLogin,
            author: message.author,
            text: message.text,
            fragments: fragments,
            timestamp: message.timestamp,
            timestampMilliseconds: message.timestampMilliseconds,
            reply: message.reply,
            reward: message.reward,
            type: message.type,
            flags: message.flags,
            outgoingState: message.outgoingState,
            outgoingError: message.outgoingError,
            clientNonce: message.clientNonce,
            serverMessageID: message.serverMessageID
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