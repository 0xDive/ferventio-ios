import Testing
@testable import FerventioDomain

struct NukePreviewTests {
    @Test
    func matchesPlainTextCaseInsensitivelyInsideWindow() throws {
        let messages = [
            makeMessage(id: "one", userID: "a", text: "OMEGALUL spam", timestamp: 29_000),
            makeMessage(id: "two", userID: "b", text: "omegalul again", timestamp: 30_000),
            makeMessage(id: "old", userID: "c", text: "OMEGALUL old", timestamp: 0),
        ]

        let preview = try #require(
            NukePreviewPlanner.build(
                messages: messages,
                config: NukePreviewConfig(query: "omegalul", windowMilliseconds: 10_000),
                nowMilliseconds: 30_000
            ).preview
        )

        #expect(preview.matchedMessageIDs == ["one", "two"])
        #expect(preview.matchedMessageCount == 2)
        #expect(preview.matchedUserCount == 2)
        #expect(preview.scannedMessageCount == 2)
    }

    @Test
    func supportsRegexAndRejectsInvalidPattern() throws {
        let preview = try #require(
            NukePreviewPlanner.build(
                messages: [makeMessage(id: "one", text: "spam123", timestamp: 1_000)],
                config: NukePreviewConfig(
                    query: "spam\\d+",
                    matchMode: .regex,
                    windowMilliseconds: 1_000
                ),
                nowMilliseconds: 1_000
            ).preview
        )
        #expect(preview.matchedMessageCount == 1)

        #expect(
            NukePreviewPlanner.build(
                messages: [],
                config: NukePreviewConfig(query: "[", matchMode: .regex),
                nowMilliseconds: 1_000
            ) == .failure(.invalidRegularExpression)
        )
    }

    @Test
    func excludesProtectedRolesAndExplicitUsers() throws {
        let messages = [
            makeMessage(
                id: "broadcaster",
                userID: "owner",
                text: "spam",
                timestamp: 1_000,
                badges: [ChatBadge(setID: "broadcaster", id: "1")]
            ),
            makeMessage(
                id: "moderator",
                userID: "mod",
                text: "spam",
                timestamp: 1_000,
                badges: [ChatBadge(setID: "moderator", id: "1")]
            ),
            makeMessage(
                id: "vip",
                userID: "vip",
                text: "spam",
                timestamp: 1_000,
                badges: [ChatBadge(setID: "vip", id: "1")]
            ),
            makeMessage(id: "explicit", userID: "safe", text: "spam", timestamp: 1_000),
            makeMessage(id: "target", userID: "target", text: "spam", timestamp: 1_000),
        ]

        let preview = try #require(
            NukePreviewPlanner.build(
                messages: messages,
                config: NukePreviewConfig(
                    query: "spam",
                    windowMilliseconds: 1_000,
                    excludedUserIDs: ["safe"]
                ),
                nowMilliseconds: 1_000
            ).preview
        )

        #expect(preview.matchedMessageIDs == ["target"])
        #expect(preview.excludedMatchCount == 4)
    }

    @Test
    func deDuplicatesUsersAndFallsBackToLoginForMissingIDs() throws {
        let messages = [
            makeMessage(id: "one", userID: "same", login: "One", text: "spam", timestamp: 1_000),
            makeMessage(id: "two", userID: "same", login: "One", text: "spam", timestamp: 1_100),
            makeMessage(id: "three", userID: "", login: "Fallback", text: "spam", timestamp: 1_200),
            makeMessage(id: "four", userID: "", login: "fallback", text: "spam", timestamp: 1_300),
        ]

        let preview = try #require(
            NukePreviewPlanner.build(
                messages: messages,
                config: NukePreviewConfig(query: "spam", windowMilliseconds: 1_000),
                nowMilliseconds: 1_500
            ).preview
        )

        #expect(preview.matchedMessageCount == 4)
        #expect(preview.matchedUserCount == 2)
        #expect(preview.matchedUserIDs == ["same", "login:fallback"])
    }

    @Test
    func scansChatAndActionButNotDeletedSystemOrFutureMessages() throws {
        let messages = [
            makeMessage(id: "chat", text: "spam", timestamp: 1_000),
            makeMessage(id: "action", text: "spam", timestamp: 1_100, type: .action),
            makeMessage(
                id: "deleted",
                text: "spam",
                timestamp: 1_200,
                flags: MessageFlags(isDeleted: true)
            ),
            makeMessage(
                id: "system",
                text: "spam",
                timestamp: 1_300,
                type: .system,
                flags: MessageFlags(isSystem: true)
            ),
            makeMessage(id: "future", text: "spam", timestamp: 2_001),
        ]

        let preview = try #require(
            NukePreviewPlanner.build(
                messages: messages,
                config: NukePreviewConfig(query: "spam", windowMilliseconds: 2_000),
                nowMilliseconds: 2_000
            ).preview
        )

        #expect(preview.matchedMessageIDs == ["chat", "action"])
        #expect(preview.scannedMessageCount == 2)
    }

    @Test
    func freezesExactPreviewTargetsWithoutReRunningQuery() throws {
        let config = NukePreviewConfig(query: " spam ")
        let preview = NukePreview(
            matchedMessageCount: 2,
            matchedUserCount: 1,
            excludedMatchCount: 0,
            scannedMessageCount: 2,
            matchedUserIDs: ["user"],
            matchedUsers: [NukeTargetUser(userID: "user", userLogin: "user", userDisplayName: "User")],
            matchedMessageIDs: ["one", "two"],
            samples: []
        )

        let plan = try #require(
            NukeExecutionPlanner.freeze(
                config: config,
                preview: preview,
                previewedAtMilliseconds: 42
            ).plan
        )

        #expect(plan.query == "spam")
        #expect(plan.previewedAtMilliseconds == 42)
        #expect(plan.targetMessageIDs == ["one", "two"])
        #expect(plan.targetUsers.map(\.userID) == ["user"])
    }

    @Test
    func validatesQueriesAndFrozenTargetConsistency() {
        #expect(
            NukePreviewPlanner.build(
                messages: [],
                config: NukePreviewConfig(query: "   "),
                nowMilliseconds: 0
            ) == .failure(.emptyQuery)
        )
        #expect(
            NukePreviewPlanner.build(
                messages: [],
                config: NukePreviewConfig(query: String(repeating: "a", count: 257)),
                nowMilliseconds: 0
            ) == .failure(.queryTooLong(maximumLength: 256))
        )

        let inconsistent = NukePreview(
            matchedMessageCount: 2,
            matchedUserCount: 1,
            excludedMatchCount: 0,
            scannedMessageCount: 2,
            matchedUserIDs: ["user"],
            matchedUsers: [NukeTargetUser(userID: "user", userLogin: "user", userDisplayName: "User")],
            matchedMessageIDs: ["one"],
            samples: []
        )
        #expect(
            NukeExecutionPlanner.freeze(
                config: NukePreviewConfig(query: "spam"),
                preview: inconsistent,
                previewedAtMilliseconds: 0
            ) == .failure(.inconsistentMessageTargetSet)
        )
    }

    private func makeMessage(
        id: String,
        userID: String = "user",
        login: String = "user",
        text: String,
        timestamp: Int64,
        badges: [ChatBadge] = [],
        type: ChatMessageType = .chat,
        flags: MessageFlags = MessageFlags()
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            channelID: "channel",
            channelLogin: "channel",
            author: ChatAuthor(
                id: userID,
                login: login,
                displayName: login,
                badges: badges
            ),
            text: text,
            timestamp: "2026-08-12T11:00:00Z",
            timestampMilliseconds: timestamp,
            type: type,
            flags: flags
        )
    }
}
