import Foundation
import FerventioDomain
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

    @Test
    func sendableMetadataRoundTripsWithoutOriginalAPNsDictionary() throws {
        let original = try #require(
            PushNotificationRoute(
                userInfo: [
                    "ferventio": [
                        "channelLogin": "Channel",
                        "messageId": "message-42",
                        "destination": "moderation",
                    ],
                ]
            )
        )

        let reconstructed = try #require(
            PushNotificationRoute(userInfo: original.notificationUserInfo)
        )

        #expect(reconstructed == original)
    }

    @Test
    func routeSessionPolicyKeepsColdLaunchRoutesButRejectsSignedOutRoutes() {
        #expect(PushNotificationRouteSessionPolicy.acceptsOpenedRoute(in: .launching))
        #expect(PushNotificationRouteSessionPolicy.acceptsOpenedRoute(in: .signedIn))
        #expect(!PushNotificationRouteSessionPolicy.acceptsOpenedRoute(in: .signedOut))
    }

    @Test
    func routeSessionPolicyClearsWhenAuthenticationEnds() {
        #expect(
            PushNotificationRouteSessionPolicy.shouldClearPendingRoute(
                previousState: .signedIn,
                currentState: .signedOut
            )
        )
        #expect(
            PushNotificationRouteSessionPolicy.shouldClearPendingRoute(
                previousState: .launching,
                currentState: .signedOut
            )
        )
        #expect(
            !PushNotificationRouteSessionPolicy.shouldClearPendingRoute(
                previousState: .launching,
                currentState: .signedIn
            )
        )
        #expect(
            !PushNotificationRouteSessionPolicy.shouldClearPendingRoute(
                previousState: .signedOut,
                currentState: .signedOut
            )
        )
    }

    @Test
    func bufferKeepsOnlyLatestRouteAndConsumesItOnce() throws {
        let buffer = PushNotificationRouteBuffer()
        let first = try #require(
            PushNotificationRoute(
                userInfo: ["ferventio": ["channelLogin": "first"]]
            )
        )
        let second = try #require(
            PushNotificationRoute(
                userInfo: ["ferventio": ["channelLogin": "second"]]
            )
        )

        buffer.store(first)
        buffer.store(second)

        #expect(buffer.takeLatest() == second)
        #expect(buffer.takeLatest() == nil)
    }

    @Test
    func bufferClearDropsPendingRoute() throws {
        let buffer = PushNotificationRouteBuffer()
        let route = try #require(
            PushNotificationRoute(
                userInfo: ["ferventio": ["channelLogin": "old-account-channel"]]
            )
        )

        buffer.store(route)
        buffer.clear()

        #expect(buffer.takeLatest() == nil)
    }
}
