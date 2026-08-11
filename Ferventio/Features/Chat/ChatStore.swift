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

    var channelInput = ""
    private(set) var channel: ChatChannel?
    private(set) var messages: [ChatMessage] = []
    private(set) var connectionState: ConnectionState = .disconnected
    var showsConnectionError = false

    @ObservationIgnored private let client: any EventSubChatStreaming
    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(client: (any EventSubChatStreaming)? = nil) {
        self.client = client ?? TwitchEventSubChatClient()
    }

    func prepareDefaultChannel(login: String) {
        if channelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            channelInput = login
        }
    }

    func connect(channel: ChatChannel, lease: TwitchAccessLease) async {
        generation &+= 1
        let currentGeneration = generation
        receiveTask?.cancel()
        receiveTask = nil
        await client.disconnect()

        self.channel = channel
        messages.removeAll(keepingCapacity: true)
        connectionState = .connecting
        showsConnectionError = false

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
        messages.removeAll(keepingCapacity: false)
        connectionState = .disconnected
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
            messages.append(message)
            trimMessagesIfNeeded()

        case .reconnected:
            connectionState = .connected

        case .revocation:
            connectionState = .failed
            showsConnectionError = true
        }
    }

    private func trimMessagesIfNeeded() {
        let overflow = messages.count - Self.maximumMessages
        if overflow > 0 {
            messages.removeFirst(overflow)
        }
    }
}
