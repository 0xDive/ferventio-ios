import Foundation
import Testing
@testable import FerventioNetworking

struct TwitchModerationAPIClientTests {
    @Test
    func buildsTimeoutRequestWithModeratorIdentityAndBoundedReason() throws {
        let request = try TwitchModerationAPIClient.makeTimeoutRequest(
            clientID: "client-1",
            accessToken: "access-1",
            broadcasterID: "broadcaster-1",
            moderatorID: "moderator-1",
            targetUserID: "target-1",
            durationSeconds: 600,
            reason: "  " + String(repeating: "r", count: 510) + "  "
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "api.twitch.tv")
        #expect(request.url?.path == "/helix/moderation/bans")
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(query["broadcaster_id"] == "broadcaster-1")
        #expect(query["moderator_id"] == "moderator-1")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(request.value(forHTTPHeaderField: "Client-Id") == "client-1")

        let body = try #require(request.httpBody)
        let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(root["data"] as? [String: Any])
        #expect(data["user_id"] as? String == "target-1")
        #expect(data["duration"] as? Int == 600)
        #expect((data["reason"] as? String)?.count == 500)
    }

    @Test
    func omitsBlankReason() throws {
        let request = try TwitchModerationAPIClient.makeTimeoutRequest(
            clientID: "client",
            accessToken: "token",
            broadcasterID: "broadcaster",
            moderatorID: "moderator",
            targetUserID: "target",
            durationSeconds: 1,
            reason: "   "
        )

        let body = try #require(request.httpBody)
        let root = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(root["data"] as? [String: Any])
        #expect(data["reason"] == nil)
    }

    @Test
    func validatesTimeoutRangeAndRequiredIdentifiers() {
        #expect(throws: TwitchModerationAPIClient.Error.invalidTimeoutDuration) {
            try TwitchModerationAPIClient.makeTimeoutRequest(
                clientID: "client",
                accessToken: "token",
                broadcasterID: "broadcaster",
                moderatorID: "moderator",
                targetUserID: "target",
                durationSeconds: 0,
                reason: "reason"
            )
        }
        #expect(throws: TwitchModerationAPIClient.Error.invalidArgument("targetUserID")) {
            try TwitchModerationAPIClient.makeTimeoutRequest(
                clientID: "client",
                accessToken: "token",
                broadcasterID: "broadcaster",
                moderatorID: "moderator",
                targetUserID: " ",
                durationSeconds: 600,
                reason: "reason"
            )
        }
    }
}
