import Testing
@testable import FerventioDomain

struct UserCardContextTests {
    @Test
    func matchesCanonicalMessagesByUserIDBeforeLogin() {
        let author = makeAuthor(id: "user", login: "viewer")
        let messages = [
            makeMessage(id: "one", author: author, timestamp: 1),
            makeMessage(id: "same-login-other-id", author: makeAuthor(id: "other", login: "viewer"), timestamp: 2),
            makeMessage(id: "two", author: makeAuthor(id: "user", login: "renamed"), timestamp: 3),
        ]

        #expect(UserCardContext.messages(for: author, in: messages).map(\.id) == ["one", "two"])
    }

    @Test
    func fallsBackToCaseInsensitiveLoginWhenUserIDIsMissing() {
        let author = makeAuthor(id: "", login: "Viewer")
        let messages = [
            makeMessage(id: "one", author: makeAuthor(id: "", login: "viewer"), timestamp: 1),
            makeMessage(id: "other", author: makeAuthor(id: "", login: "someone"), timestamp: 2),
        ]

        #expect(UserCardContext.messages(for: author, in: messages).map(\.id) == ["one"])
    }

    @Test
    func returnsNewestRecentMessagesFirstWithinLimit() {
        let author = makeAuthor(id: "user", login: "viewer")
        let messages = (1...5).map { index in
            makeMessage(id: "m\(index)", author: author, timestamp: Int64(index))
        }

        #expect(
            UserCardContext.recentMessages(for: author, in: messages, limit: 3).map(\.id)
                == ["m5", "m4", "m3"]
        )
    }

    @Test
    func reportsProtectedRolesInStableOrder() {
        let author = ChatAuthor(
            id: "user",
            login: "viewer",
            displayName: "Viewer",
            badges: [
                ChatBadge(setID: "subscriber", id: "1"),
                ChatBadge(setID: "vip", id: "1"),
                ChatBadge(setID: "moderator", id: "1"),
            ]
        )

        #expect(UserCardContext.protectedRoleBadgeSetIDs(for: author) == ["moderator", "vip"])
    }

    private func makeAuthor(id: String, login: String) -> ChatAuthor {
        ChatAuthor(id: id, login: login, displayName: login)
    }

    private func makeMessage(id: String, author: ChatAuthor, timestamp: Int64) -> ChatMessage {
        ChatMessage(
            id: id,
            channelID: "channel",
            channelLogin: "channel",
            author: author,
            text: id,
            timestamp: "2026-08-12T11:00:00Z",
            timestampMilliseconds: timestamp
        )
    }
}
