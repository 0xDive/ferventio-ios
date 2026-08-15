import Foundation
import Testing
@testable import Ferventio

struct PushNotificationRouteTests {
    @Test
    func parsesBackendAPNsPayloadAndNormalizesChannelLogin() throws {
        let route = try #require(
            PushNotificationRoute(
                userInfo: [
                    "aps": ["alert": ["body": "You were mentioned"]],
                    "ferventio": [
                        "type": "mention",
                        "channelLogin": "  SomeChannel  ",
                        "messageId": " message-123 ",
                        "destination": " chat ",
                    ],
                ]
            )
        )

        #expect(route.channelLogin == "somechannel")
        #expect(route.messageID == "message-123")
        #expect(route.destination == "chat")
    }

    @Test
    func acceptsAnyHashableNestedPayloadFromNotificationCenter() throws {
        let nested: [AnyHashable: Any] = [
            AnyHashable("channelLogin"): "ferventio",
            AnyHashable("messageId"): "abc",
        ]

        let route = try #require(
            PushNotificationRoute(userInfo: [AnyHashable("ferventio"): nested])
        )

        #expect(route.channelLogin == "ferventio")
        #expect(route.messageID == "abc")
    }

    @Test
    func rejectsMissingOrBlankChannelLogin() {
        #expect(PushNotificationRoute(userInfo: [:]) == nil)
        #expect(
            PushNotificationRoute(
                userInfo: ["ferventio": ["channelLogin": "   "]]
            ) == nil
        )
    }

    @Test
    func ignoresBlankOptionalNavigationMetadata() throws {
        let route = try #require(
            PushNotificationRoute(
                userInfo: [
                    "ferventio": [
                        "channelLogin": "channel",
                        "messageId": " ",
                        "destination": "\n",
                    ],
                ]
            )
        )

        #expect(route.messageID == nil)
        #expect(route.destination == nil)
    }
}
