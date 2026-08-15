import FerventioDomain
import Testing
@testable import FerventioNetworking

struct EventSubChannelScopeTests {
    @Test
    func acceptsMessageForActiveChannel() {
        let envelope = EventSubEnvelope(
            messageType: "notification",
            messageID: "event-1",
            chatMessage: message(channelID: "channel-a")
        )

        #expect(EventSubChannelScope.accepts(envelope, activeChannelID: "channel-a"))
    }

    @Test
    func rejectsMessageForDifferentChannel() {
        let envelope = EventSubEnvelope(
            messageType: "notification",
            messageID: "event-1",
            chatMessage: message(channelID: "channel-a")
        )

        #expect(!EventSubChannelScope.accepts(envelope, activeChannelID: "channel-b"))
    }

    @Test
    func acceptsUnscopedAndPreConnectionEnvelopes() {
        let unknownNotification = EventSubEnvelope(
            messageType: "notification",
            messageID: "event-1"
        )
        let keepalive = EventSubEnvelope(messageType: "session_keepalive")
        let messageEnvelope = EventSubEnvelope(
            messageType: "notification",
            messageID: "event-2",
            chatMessage: message(channelID: "channel-a")
        )

        #expect(EventSubChannelScope.accepts(unknownNotification, activeChannelID: "channel-b"))
        #expect(EventSubChannelScope.accepts(keepalive, activeChannelID: "channel-b"))
        #expect(EventSubChannelScope.accepts(messageEnvelope, activeChannelID: nil))
    }

    private func message(channelID: String) -> ChatMessage {
        ChatMessage(
            id: "message-1",
            channelID: channelID,
            channelLogin: "channel",
            author: ChatAuthor(
                id: "user",
                login: "viewer",
                displayName: "Viewer"
            ),
            text: "Hello",
            timestamp: "2026-08-15T19:00:00Z",
            timestampMilliseconds: 1
        )
    }
}
