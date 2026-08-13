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
    func parsesPollProgressSnapshot() throws {
        let raw = """
        {
          "metadata": {"message_id":"poll-event-1","message_type":"notification","message_timestamp":"2026-08-11T09:00:05Z"},
          "payload": {
            "subscription": {"type":"channel.poll.progress"},
            "event": {
              "id":"poll-1",
              "broadcaster_user_id":"100",
              "title":"Best color?",
              "choices":[
                {"id":"a","title":"Blue","bits_votes":2,"channel_points_votes":3,"votes":5},
                {"id":"b","title":"Pink","bits_votes":1,"channel_points_votes":4,"votes":5}
              ],
              "bits_voting":{"is_enabled":true,"amount_per_vote":10},
              "channel_points_voting":{"is_enabled":true,"amount_per_vote":50},
              "started_at":"2026-08-11T09:00:00Z",
              "ends_at":"2026-08-11T09:01:00Z"
            }
          }
        }
        """

        let envelope = try EventSubEnvelopeParser.parse(raw)
        let poll = try #require(envelope.poll)

        #expect(envelope.subscriptionType == "channel.poll.progress")
        #expect(poll.id == "poll-1")
        #expect(poll.channelID == "100")
        #expect(poll.status == .active)
        #expect(poll.totalVotes == 10)
        #expect(poll.choices[0].channelPointsVotes == 3)
        #expect(poll.channelPointsVotingEnabled)
        #expect(poll.channelPointsPerVote == 50)
        #expect(poll.bitsVotingEnabled)
        #expect(poll.bitsPerVote == 10)
        #expect(poll.endsAtMilliseconds != nil)
        #expect(poll.updatedAtMilliseconds > poll.startedAtMilliseconds)
    }

    @Test
    func parsesPollEndStatusAndEndedAt() throws {
        let raw = """
        {
          "metadata": {"message_type":"notification","message_timestamp":"2026-08-11T09:01:01Z"},
          "payload": {
            "subscription": {"type":"channel.poll.end"},
            "event": {
              "id":"poll-1","broadcaster_user_id":"100","title":"Best color?",
              "choices":[{"id":"a","title":"Blue","votes":12}],
              "status":"terminated",
              "started_at":"2026-08-11T09:00:00Z",
              "ended_at":"2026-08-11T09:01:00Z"
            }
          }
        }
        """

        let poll = try #require(EventSubEnvelopeParser.parse(raw).poll)

        #expect(poll.status == .terminated)
        #expect(poll.endedAtMilliseconds != nil)
        #expect(!poll.isActive)
    }

    @Test
    func parsesPredictionLockSnapshot() throws {
        let raw = """
        {
          "metadata": {"message_type":"notification","message_timestamp":"2026-08-11T09:05:00Z"},
          "payload": {
            "subscription": {"type":"channel.prediction.lock"},
            "event": {
              "id":"prediction-1","broadcaster_user_id":"100","title":"Will it happen?",
              "outcomes":[
                {"id":"yes","title":"Yes","color":"blue","users":10,"channel_points":15000},
                {"id":"no","title":"No","color":"pink","users":5,"channel_points":5000}
              ],
              "started_at":"2026-08-11T09:00:00Z",
              "locked_at":"2026-08-11T09:05:00Z"
            }
          }
        }
        """

        let prediction = try #require(EventSubEnvelopeParser.parse(raw).prediction)

        #expect(prediction.status == .locked)
        #expect(prediction.isLocked)
        #expect(prediction.totalUsers == 15)
        #expect(prediction.totalChannelPoints == 20_000)
        #expect(prediction.outcomes[0].color == .blue)
        #expect(prediction.lockedAtMilliseconds != nil)
    }

    @Test
    func parsesPredictionEndWinnerAndStatus() throws {
        let raw = """
        {
          "metadata": {"message_type":"notification","message_timestamp":"2026-08-11T09:06:00Z"},
          "payload": {
            "subscription": {"type":"channel.prediction.end"},
            "event": {
              "id":"prediction-1","broadcaster_user_id":"100","title":"Will it happen?",
              "winning_outcome_id":"yes",
              "outcomes":[
                {"id":"yes","title":"Yes","color":"blue","users":10,"channel_points":15000},
                {"id":"no","title":"No","color":"pink","users":5,"channel_points":5000}
              ],
              "status":"resolved",
              "started_at":"2026-08-11T09:00:00Z",
              "ended_at":"2026-08-11T09:06:00Z"
            }
          }
        }
        """

        let prediction = try #require(EventSubEnvelopeParser.parse(raw).prediction)

        #expect(prediction.status == .resolved)
        #expect(prediction.winningOutcomeID == "yes")
        #expect(prediction.endedAtMilliseconds != nil)
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

    @Test
    func rejectsInteractiveEventWithoutBroadcasterIdentity() {
        let raw = """
        {"metadata":{"message_type":"notification"},"payload":{"subscription":{"type":"channel.poll.begin"},"event":{"id":"poll-1","started_at":"2026-08-11T09:00:00Z"}}}
        """

        #expect(throws: EventSubEnvelopeParser.Error.missingField("broadcaster_user_id")) {
            try EventSubEnvelopeParser.parse(raw)
        }
    }
}
