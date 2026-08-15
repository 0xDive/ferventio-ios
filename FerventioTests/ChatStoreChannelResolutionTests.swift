import FerventioDomain
import FerventioNetworking
import Testing
@testable import Ferventio

@MainActor
struct ChatStoreChannelResolutionTests {
    @Test
    func failurePreservesExistingLiveConnectionState() async {
        let eventSub = ChannelResolutionStubEventSubClient()
        let store = ChatStore(client: eventSub)
        let channel = ChatChannel(
            id: "channel",
            login: "channel",
            displayName: "Channel"
        )

        await store.connect(
            channel: channel,
            lease: makeLease(),
            currentUser: nil
        )
        #expect(store.connectionState == .connected)

        store.failChannelResolution()

        #expect(store.connectionState == .connected)
        #expect(store.showsConnectionError)
        #expect(store.channel == channel)
        await store.disconnect()
    }

    @Test
    func failureMarksDisconnectedStoreFailed() {
        let store = ChatStore()

        store.failChannelResolution()

        #expect(store.connectionState == .failed)
        #expect(store.showsConnectionError)
    }

    private func makeLease() -> TwitchAccessLease {
        TwitchAccessLease(
            accessToken: "access",
            leaseExpiresAtEpochMilliseconds: 100_000,
            twitchExpiresAtEpochMilliseconds: 200_000,
            twitchValidatedAtEpochMilliseconds: 50_000,
            backendSessionExpiresAtEpochMilliseconds: 300_000,
            session: TwitchSession(
                clientID: "client",
                userID: "user",
                login: "viewer",
                scopes: ["user:read:chat"],
                expiresInSeconds: 200
            )
        )
    }
}

private actor ChannelResolutionStubEventSubClient: EventSubChatStreaming {
    func connect(
        channel: ChatChannel,
        lease: TwitchAccessLease
    ) async throws -> EventSubSubscription {
        EventSubSubscription(
            id: "subscription",
            status: "enabled",
            type: "channel.chat.message",
            version: "1",
            cost: 0,
            sessionID: "session"
        )
    }

    func nextEvent() async throws -> TwitchEventSubChatClient.Event {
        try await Task.sleep(for: .seconds(3_600))
        throw CancellationError()
    }

    func disconnect() async {}
}
