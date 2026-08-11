import Foundation
import FerventioDomain
import Testing
@testable import FerventioNetworking

struct TwitchRecentMessagesClientTests {
    @Test
    func parsesIrcSnapshotWithBadgesEmotesRepliesAndErrorCode() throws {
        let line = "@badges=moderator/1;color=#9146FF;display-name=Viewer;emotes=25:0-4;first-msg=1;id=m1;login=viewer;reply-parent-msg-body=hello\\sworld;reply-parent-msg-id=p1;reply-parent-user-id=u2;reply-parent-user-login=parent;reply-parent-display-name=Parent;rm-received-ts=1000;room-id=channel;user-id=u1 :viewer!viewer@viewer.tmi.twitch.tv PRIVMSG #channel :Kappa hi"
        let data = try makePayload(messages: [line], errorCode: "channel_not_joined")

        let result = try TwitchRecentMessagesClient.parseResponse(
            data,
            channel: makeChannel(),
            limit: 100,
            nowMilliseconds: { 9_999 }
        )

        #expect(result.errorCode == "channel_not_joined")
        #expect(result.messages.count == 1)
        let message = try #require(result.messages.first)
        #expect(message.id == "m1")
        #expect(message.timestampMilliseconds == 1_000)
        #expect(message.author.id == "u1")
        #expect(message.author.displayName == "Viewer")
        #expect(message.author.color == "#9146FF")
        #expect(message.author.badges == [ChatBadge(setID: "moderator", id: "1")])
        #expect(message.flags.isFirstMessage)
        #expect(message.reply?.parentMessageID == "p1")
        #expect(message.reply?.parentMessageBody == "hello world")
        #expect(message.fragments == [
            .twitchEmote(
                text: "Kappa",
                emoteID: "25",
                emoteSetID: nil,
                ownerID: nil,
                formats: []
            ),
            .text(" hi"),
        ])
    }

    @Test
    func actionOffsetsIrcEmoteRangesBeforeBuildingFragments() throws {
        let action = "\u{1}ACTION Kappa wave\u{1}"
        let line = "@display-name=Viewer;emotes=25:8-12;id=action-1;login=viewer;tmi-sent-ts=2000;user-id=u1 :viewer!viewer@host PRIVMSG #channel :\(action)"
        let result = try TwitchRecentMessagesClient.parseResponse(
            makePayload(messages: [line]),
            channel: makeChannel(),
            limit: 100
        )

        let message = try #require(result.messages.first)
        #expect(message.text == "Kappa wave")
        #expect(message.type == .action)
        #expect(message.flags.isAction)
        #expect(message.fragments.first == .twitchEmote(
            text: "Kappa",
            emoteID: "25",
            emoteSetID: nil,
            ownerID: nil,
            formats: []
        ))
    }

    @Test
    func snapshotAppliesDeleteAndUserClearEvents() throws {
        let first = "@display-name=One;id=m1;login=one;tmi-sent-ts=1000;user-id=u1 :one!one@host PRIVMSG #channel :first"
        let second = "@display-name=Two;id=m2;login=two;tmi-sent-ts=2000;user-id=u2 :two!two@host PRIVMSG #channel :second"
        let clearMessage = "@target-msg-id=m2;tmi-sent-ts=2500 :tmi.twitch.tv CLEARMSG #channel :second"
        let clearUser = "@target-user-id=u1;tmi-sent-ts=3000 :tmi.twitch.tv CLEARCHAT #channel :one"

        let result = try TwitchRecentMessagesClient.parseResponse(
            makePayload(messages: [first, second, clearMessage, clearUser]),
            channel: makeChannel(),
            limit: 100
        )

        #expect(result.messages.count == 2)
        #expect(result.messages.first(where: { $0.id == "m1" })?.flags.isDeleted == true)
        #expect(result.messages.first(where: { $0.id == "m2" })?.flags.isDeleted == true)
    }

    @Test
    func channelClearDropsEarlierSnapshotMessages() throws {
        let first = "@display-name=One;id=m1;login=one;tmi-sent-ts=1000;user-id=u1 :one!one@host PRIVMSG #channel :first"
        let clear = "@tmi-sent-ts=2000 :tmi.twitch.tv CLEARCHAT #channel"
        let after = "@display-name=Two;id=m2;login=two;tmi-sent-ts=3000;user-id=u2 :two!two@host PRIVMSG #channel :after"

        let result = try TwitchRecentMessagesClient.parseResponse(
            makePayload(messages: [first, clear, after]),
            channel: makeChannel(),
            limit: 100
        )

        #expect(result.messages.map(\.id) == ["m2"])
    }

    @Test
    func parserIgnoresOtherChannelsAndOversizedLinesAndKeepsLatestLimit() throws {
        let other = "@id=other;tmi-sent-ts=1000 :viewer!viewer@host PRIVMSG #other :wrong"
        let oversized = String(repeating: "x", count: TwitchIRCRecentSnapshotParser.maximumLineCharacters + 1)
        let lines = (0..<5).map { index in
            "@display-name=Viewer;id=m\(index);login=viewer;tmi-sent-ts=\(2_000 + index);user-id=u1 :viewer!viewer@host PRIVMSG #channel :message \(index)"
        }

        let result = try TwitchRecentMessagesClient.parseResponse(
            makePayload(messages: [other, oversized] + lines),
            channel: makeChannel(),
            limit: 2
        )

        #expect(result.messages.map(\.id) == ["m3", "m4"])
    }

    @Test
    func validatesBaseURLAndChannelLogin() async throws {
        #expect(throws: TwitchRecentMessagesClient.Error.invalidBaseURL) {
            try TwitchRecentMessagesClient(baseURL: URL(string: "http://example.com/recent")!)
        }

        let client = try TwitchRecentMessagesClient()
        await #expect(throws: TwitchRecentMessagesClient.Error.invalidChannelLogin) {
            try await client.load(
                channel: ChatChannel(id: "1", login: "not-valid!", displayName: "Invalid")
            )
        }
    }

    private func makeChannel() -> ChatChannel {
        ChatChannel(id: "channel", login: "channel", displayName: "Channel")
    }

    private func makePayload(
        messages: [String],
        errorCode: String? = nil
    ) throws -> Data {
        var payload: [String: Any] = ["messages": messages]
        if let errorCode {
            payload["error_code"] = errorCode
        }
        return try JSONSerialization.data(withJSONObject: payload)
    }
}
