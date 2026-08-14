import XCTest
@testable import FerventioSupport

final class SettingsBackupCodecTests: XCTestCase {
    func testMatchesAndroidVersionTwoSampleHash() throws {
        let content = makeAndroidSampleContent()

        XCTAssertEqual(
            SettingsBackupCodec.contentHash(content),
            "4683c3f1b6ab4f0f41944a0775110930f1f337ae2d1169f399fba430cbbbae83"
        )
    }

    func testDecodesAndroidVersionTwoSample() throws {
        let raw = #"{"format":"ferventio-settings-backup","formatVersion":2,"createdAt":"2026-07-25T12:00:00Z","appVersion":"0.0.1-test","contentHash":"4683c3f1b6ab4f0f41944a0775110930f1f337ae2d1169f399fba430cbbbae83","content":{"settings":{"appLanguage":"RUSSIAN","themeMode":"AMOLED","fontScalePercent":115,"messageDensity":"COMPACT","showAvatars":false,"showBadges":true,"showTimestamps":true,"nameStyle":"DISPLAY_AND_LOGIN","wrapMessageLines":true,"showDeletedMessageContent":true,"showSystemMessages":false,"mentionColorArgb":4294953047,"autoScrollEnabled":true,"repeatCollapseEnabled":false,"animateEmotes":true,"emoteScalePercent":125,"betterTtvEnabled":true,"frankerFaceZEnabled":true,"sevenTvEnabled":true,"sendOnEnter":true,"showComposerEmoteImages":true,"replyNotificationsEnabled":true,"autoModNotificationsEnabled":true,"recentMessagesEnabled":true,"localHistoryEnabled":true,"localHistoryLimit":500,"localHistoryRetentionDays":30,"localHistoryMaxSizeMb":250,"userCardTimeoutPresetsSeconds":[10,60,600],"userCardShowBanAction":true,"userCardModerationActionOrder":["timeout:10","ban","unban"]},"channels":{"logins":["channel_a","channel_b"],"selectedLogin":"channel_a","favouriteChannelIds":["1"],"pinnedChannelIds":["1"],"recentChannelIds":["2"],"tabTitles":{}},"workspaces":null,"filters":{},"highlights":[],"ignoreRules":[],"commands":{},"favouriteEmotes":["provider:emote"]}}"#

        let decoded = try SettingsBackupCodec.decode(raw)

        XCTAssertEqual(decoded.formatVersion, 2)
        XCTAssertEqual(decoded.content.channels.logins, ["channel_a", "channel_b"])
        XCTAssertEqual(decoded.content.channels.selectedLogin, "channel_a")
        XCTAssertFalse(decoded.content.settings.showSystemMessages)
        XCTAssertFalse(decoded.content.settings.repeatCollapseEnabled)
        XCTAssertTrue(decoded.content.settings.recentMessagesEnabled)
        XCTAssertEqual(decoded.content.favouriteEmotes, ["provider:emote"])
    }

    func testTamperedContentIsRejected() throws {
        let document = try SettingsBackupCodec.makeDocument(
            content: makeAndroidSampleContent(),
            appVersion: "0.0.1-test",
            createdAt: "2026-07-25T12:00:00Z"
        )
        let raw = try SettingsBackupCodec.encode(document, pretty: false)
        let tampered = raw.replacingOccurrences(of: "channel_a", with: "channel_x")

        XCTAssertThrowsError(try SettingsBackupCodec.decode(tampered)) { error in
            XCTAssertEqual(error as? SettingsBackupError, .checksumMismatch)
        }
    }

    func testVersionOneCannotOverrideRepeatCollapse() throws {
        var content = makeAndroidSampleContent()
        content.settings.repeatCollapseEnabled = false
        let document = try SettingsBackupCodec.makeDocument(
            content: content,
            appVersion: "0.0.1-test",
            createdAt: "2026-07-25T12:00:00Z",
            formatVersion: 1
        )
        let raw = try SettingsBackupCodec.encode(document, pretty: false)

        let decoded = try SettingsBackupCodec.decode(raw)

        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertTrue(decoded.content.settings.repeatCollapseEnabled)
    }

    func testGenericJSONObjectOrderSurvivesRoundTrip() throws {
        var content = makeAndroidSampleContent()
        content.filters = .object([
            .init(key: "schemaVersion", value: .number("1")),
            .init(
                key: "filters",
                value: .array([
                    .object([
                        .init(key: "id", value: .string("filter-1")),
                        .init(key: "name", value: .string("Links")),
                        .init(key: "expression", value: .string("has:link")),
                    ]),
                ])
            ),
        ])
        let document = try SettingsBackupCodec.makeDocument(
            content: content,
            appVersion: "0.0.1-test",
            createdAt: "2026-07-25T12:00:00Z"
        )
        let encoded = try SettingsBackupCodec.encode(document, pretty: true)

        let decoded = try SettingsBackupCodec.decode(encoded)

        XCTAssertEqual(decoded.content.filters, content.filters)
        XCTAssertEqual(decoded.contentHash, document.contentHash)
    }

    func testRejectsExcessiveJSONDepthBeforeParsing() {
        let raw = String(repeating: "[", count: SettingsBackupFormat.maximumJSONDepth + 1)
            + "null"
            + String(repeating: "]", count: SettingsBackupFormat.maximumJSONDepth + 1)

        XCTAssertThrowsError(try SettingsBackupCodec.decode(raw)) { error in
            XCTAssertEqual(error as? SettingsBackupError, .nestingTooDeep)
        }
    }

    private func makeAndroidSampleContent() -> SettingsBackupContent {
        SettingsBackupContent(
            settings: SettingsBackupSettings(
                themeMode: "AMOLED",
                fontScalePercent: 115,
                messageDensity: "COMPACT",
                showAvatars: false,
                showBadges: true,
                showTimestamps: true,
                nameStyle: "DISPLAY_AND_LOGIN",
                wrapMessageLines: true,
                showDeletedMessageContent: true,
                showSystemMessages: false,
                mentionColorArgb: 0xFFFFC857,
                autoScrollEnabled: true,
                repeatCollapseEnabled: false,
                animateEmotes: true,
                emoteScalePercent: 125,
                betterTtvEnabled: true,
                frankerFaceZEnabled: true,
                sevenTvEnabled: true,
                sendOnEnter: true,
                showComposerEmoteImages: true,
                replyNotificationsEnabled: true,
                autoModNotificationsEnabled: true,
                recentMessagesEnabled: true,
                localHistoryEnabled: true,
                localHistoryLimit: 500,
                localHistoryRetentionDays: 30,
                localHistoryMaxSizeMb: 250,
                userCardTimeoutPresetsSeconds: [10, 60, 600],
                userCardShowBanAction: true,
                userCardModerationActionOrder: ["timeout:10", "ban", "unban"]
            ),
            channels: SettingsBackupChannels(
                logins: ["channel_a", "channel_b"],
                selectedLogin: "channel_a",
                favouriteChannelIds: ["1"],
                pinnedChannelIds: ["1"],
                recentChannelIds: ["2"]
            ),
            favouriteEmotes: ["provider:emote"]
        )
    }
}
