import Foundation
import FerventioDomain
import Testing
@testable import FerventioNetworking

struct EventSubEnvelopeParserTests {
    @Test
    func parsesSessionWelcome() throws {
        let raw = """
        {"metadata":{"message_id":"welcome-1","message_type":"session_welcome","message_timestamp":"2026-08-11T09:00:00Z"},"payload":{"session":{"id":"session-1","keepalive_timeout_seconds":30,"reconnect_url":null}}}
        """

        let envelope = try EventSubEnvelopeParser.parse(raw)

        #expect(envelope.messageType == "session_welcome")
        #expect(envelope.messageID == "welcome-1")
        #expect(envelope.sessionID == "session-1")
        #expect(envelope.keepaliveTimeoutSeconds == 30)
    }

    @Test
    func parsesChatMessageWithBadgesFragmentsAndReply() throws {
        let raw = """
        {
          "metadata": {
            "message_id": "event-1",
            "message_type": "notification",
            "message_timestamp": "2026-08-11T09:00:00Z"
          },
          "payload": {
            "subscription": {"type": "channel.chat.message"},
            "event": {
              "broadcaster_user_id": "100",
              "broadcaster_user_login": "channel",
              "chatter_user_id": "200",
              "chatter_user_login": "alice",
              "chatter_user_name": "Alice",
              "color": "#FF0000",
              "message_id": "message-1",
              "message_type": "text",
              "badges": [{"set_id": "subscriber", "id": "12", "info": ""}],
              "reply": {
                "parent_message_id": "parent-1",
                "parent_user_id": "300",
                "parent_user_login": "bob",
                "parent_user_name": "Bob"
              },
              "message": {
                "text": "@Bob hi Kappa",
                "fragments": [
                  {
                    "type": "mention",
                    "text": "@Bob",
                    "mention": {"user_id": "300", "user_login": "bob", "user_name": "Bob"}
                  },
                  {"type": "text", "text": " hi "},
                  {
                    "type": "emote",
                    "text": "Kappa",
                    "emote": {"id": "25", "emote_set_id": "0", "owner_id": "0", "format": ["static"]}
                  }
                ]
              }
            }
          }
        }
        """

        let envelope = try EventSubEnvelopeParser.parse(raw)
        let message = try #require(envelope.chatMessage)

        #expect(envelope.subscriptionType == "channel.chat.message")
        #expect(message.eventSubMessageID == "event-1")
        #expect(message.id == "message-1")
        #expect(message.channelID == "100")
        #expect(message.author.login == "alice")
        #expect(message.author.badges == [ChatBadge(setID: "subscriber", id: "12", info: "")])
        #expect(message.text == "hi Kappa")
        #expect(message.reply?.parentMessageID == "parent-1")
        #expect(message.fragments == [
            .text("hi "),
            .twitchEmote(text: "Kappa", emoteID: "25", emoteSetID: "0", ownerID: "0", formats: ["static"]),
        ])
    }

    @Test
    func rejectsOversizedEnvelopeBeforeJSONParsing() {
        let raw = String(repeating: "x", count: EventSubEnvelopeParser.maximumEnvelopeBytes + 1)

        #expect(throws: EventSubEnvelopeParser.Error.payloadTooLarge) {
            try EventSubEnvelopeParser.parse(raw)
        }
    }

    @Test
    func rejectsChatMessageWithoutRequiredIdentity() {
        let raw = """
        {"metadata":{"message_type":"notification"},"payload":{"subscription":{"type":"channel.chat.message"},"event":{"message_id":"message-1","broadcaster_user_id":"100","message":{"text":"hello"}}}}
        """

        #expect(throws: EventSubEnvelopeParser.Error.missingField("chatter_user_id")) {
            try EventSubEnvelopeParser.parse(raw)
        }
    }
}
