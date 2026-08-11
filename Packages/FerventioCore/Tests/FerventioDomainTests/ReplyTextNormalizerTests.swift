import Testing
@testable import FerventioDomain

struct ReplyTextNormalizerTests {
    @Test
    func removesLeadingReplyMentionAndSeparator() {
        let reply = ReplyContext(
            parentMessageID: "parent",
            parentUserLogin: "alice",
            parentUserName: "Alice"
        )

        let result = ReplyTextNormalizer.normalize(
            text: "@Alice: hello there",
            fragments: [.mention(text: "@Alice", userID: "1", userLogin: "alice", userName: "Alice"), .text(": hello there")],
            reply: reply
        )

        #expect(result.text == "hello there")
        #expect(result.fragments == [.text("hello there")])
    }

    @Test
    func preservesMentionWhenItDoesNotMatchReplyParent() {
        let reply = ReplyContext(parentMessageID: "parent", parentUserLogin: "alice")

        let result = ReplyTextNormalizer.normalize(
            text: "@bob hello",
            fragments: [.text("@bob hello")],
            reply: reply
        )

        #expect(result.text == "@bob hello")
        #expect(result.fragments == [.text("@bob hello")])
    }

    @Test
    func preservesSecondIntentionalMention() {
        let reply = ReplyContext(parentMessageID: "parent", parentUserLogin: "alice")

        let result = ReplyTextNormalizer.normalize(
            text: "@alice @alice thanks",
            fragments: [.text("@alice @alice thanks")],
            reply: reply
        )

        #expect(result.text == "@alice thanks")
    }
}
