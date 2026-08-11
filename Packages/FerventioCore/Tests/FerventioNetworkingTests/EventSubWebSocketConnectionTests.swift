import Foundation
import Testing
@testable import FerventioNetworking

struct EventSubWebSocketConnectionTests {
    @Test
    func acceptsDefaultAndReconnectTwitchURLs() {
        #expect(EventSubWebSocketConnection.isAllowedEventSubURL(EventSubWebSocketConnection.defaultURL))
        #expect(
            EventSubWebSocketConnection.isAllowedEventSubURL(
                URL(string: "wss://eventsub.wss.twitch.tv/ws?session=opaque-token")!
            )
        )
    }

    @Test
    func rejectsNonTLSOrForeignEventSubURLs() {
        #expect(
            !EventSubWebSocketConnection.isAllowedEventSubURL(
                URL(string: "ws://eventsub.wss.twitch.tv/ws")!
            )
        )
        #expect(
            !EventSubWebSocketConnection.isAllowedEventSubURL(
                URL(string: "wss://example.com/ws")!
            )
        )
        #expect(
            !EventSubWebSocketConnection.isAllowedEventSubURL(
                URL(string: "wss://user@eventsub.wss.twitch.tv/ws")!
            )
        )
    }
}
