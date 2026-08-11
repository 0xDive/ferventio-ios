import Foundation
import Testing
@testable import FerventioNetworking

struct TwitchChatAPIClientTests {
    @Test
    func buildsSendMessageRequestWithReply() throws {
        let request = try TwitchChatAPIClient.makeSendMessageRequest(
            clientID: "client-1",
            accessToken: "access-1",
            broadcasterID: "broadcaster-1",
            senderID: "user-1",
            message: "Hello chat",
            replyParentMessageID: "parent-1"
        )

        #expect(request.url?.absoluteString == "https://api.twitch.tv/helix/chat/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(request.value(forHTTPHeaderField: "Client-Id") == "client-1")

        let data = try #require(request.httpBody)
        let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["broadcaster_id"] as? String == "broadcaster-1")
        #expect(root["sender_id"] as? String == "user-1")
        #expect(root["message"] as? String == "Hello chat")
        #expect(root["reply_parent_message_id"] as? String == "parent-1")
        #expect(root["for_source_only"] == nil)
    }

    @Test
    func rejectsMessagesLongerThanTwitchLimit() {
        #expect(throws: TwitchChatAPIClient.Error.messageTooLong) {
            try TwitchChatAPIClient.makeSendMessageRequest(
                clientID: "client-1",
                accessToken: "access-1",
                broadcasterID: "broadcaster-1",
                senderID: "user-1",
                message: String(repeating: "a", count: 501)
            )
        }
    }

    @Test
    func rejectsWhitespaceOnlyMessage() {
        #expect(throws: TwitchChatAPIClient.Error.invalidArgument("message")) {
            try TwitchChatAPIClient.makeSendMessageRequest(
                clientID: "client-1",
                accessToken: "access-1",
                broadcasterID: "broadcaster-1",
                senderID: "user-1",
                message: "   "
            )
        }
    }
}
