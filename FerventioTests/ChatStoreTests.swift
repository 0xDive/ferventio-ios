import FerventioDomain
import FerventioNetworking
import Testing
@testable import Ferventio

@MainActor
struct ChatStoreTests {
    @Test
    func boundsInMemoryMessageBuffer() {
        let store = ChatStore()

        for index in 0..<(ChatStore.maximumMessages + 5) {
            store.apply(.message(makeMessage(index)))
        }

        #expect(store.messages.count == ChatStore.maximumMessages)
        #expect(store.messages.first?.id == "message-5")
        #expect(store.messages.last?.id == "message-2004")
    }

    @Test
    func reconnectEventReturnsStoreToConnectedState() {
        let store = ChatStore()

        store.apply(.reconnected(sessionID: "session-2"))

        #expect(store.connectionState == .connected)
    }

    @Test
    func revocationMarksConnectionAsFailed() {
        let store = ChatStore()

        store.apply(.revocation(subscriptionType: "channel.chat.message", status: "version_removed"))

        #expect(store.connectionState == .failed)
        #expect(store.showsConnectionError)
    }

    private func makeMessage(_ index: Int) -> ChatMessage {
        ChatMessage(
            id: "message-\(index)",
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(
                id: "user",
                login: "viewer",
                displayName: "Viewer"
            ),
            text: "Message \(index)",
            timestamp: "2026-08-11T09:00:00Z",
            timestampMilliseconds: Int64(index)
        )
    }
}
