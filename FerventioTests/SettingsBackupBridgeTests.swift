import Foundation
import FerventioDomain
import FerventioSupport
import Testing
@testable import Ferventio

@MainActor
struct SettingsBackupBridgeTests {
    @Test
    func captureMapsSupportedIOSStateIntoAndroidVersionTwoDocument() throws {
        let firstID = UUID()
        let secondID = UUID()
        let rule = ChatPresentationRule(
            action: .highlight,
            target: .message,
            query: "important"
        )
        let history = ChatHistoryPreferences(
            recentMessagesEnabled: false,
            localHistoryEnabled: true,
            localHistoryLimit: 1_250,
            retentionDays: 30,
            maxDatabaseSizeMB: 256
        )
        let presentation = ChatPresentationPreferences(
            repeatCollapseEnabled: false,
            rules: [rule]
        )
        let snapshot = ChatWorkspaceRegistrySnapshot(
            workspaces: [
                ChatWorkspace(id: firstID, login: "alpha"),
                ChatWorkspace(id: secondID, login: "beta"),
            ],
            activeWorkspaceID: secondID
        )

        let export = try SettingsBackupBridge.capture(
            historyPreferences: history,
            presentationPreferences: presentation,
            workspaceSnapshot: snapshot,
            appVersion: "0.0.1-test",
            createdAt: "2026-08-14T17:30:00Z"
        )

        #expect(export.document.format == SettingsBackupFormat.identifier)
        #expect(export.document.formatVersion == 2)
        #expect(export.document.content.settings.recentMessagesEnabled == false)
        #expect(export.document.content.settings.localHistoryEnabled)
        #expect(export.document.content.settings.localHistoryLimit == 1_250)
        #expect(export.document.content.settings.localHistoryRetentionDays == 30)
        #expect(export.document.content.settings.localHistoryMaxSizeMb == 256)
        #expect(export.document.content.settings.repeatCollapseEnabled == false)
        #expect(export.document.content.channels.logins == ["alpha", "beta"])
        #expect(export.document.content.channels.selectedLogin == "beta")
        #expect(export.document.content.highlights == .emptyArray)
        #expect(export.document.content.ignoreRules == .emptyArray)
        #expect(export.omittedPresentationRuleCount == 1)

        let raw = try SettingsBackupBridge.encode(export, pretty: false)
        let decoded = try SettingsBackupCodec.decode(raw)
        #expect(decoded == export.document)
        #expect(!raw.contains("accessToken"))
        #expect(!raw.contains("refreshToken"))
        #expect(!raw.contains("installationSecret"))
    }

    @Test
    func importPlanPreservesIOSRulesAndAppliesOnlySupportedSettings() throws {
        let existingRule = ChatPresentationRule(
            action: .hide,
            target: .author,
            matchMode: .contains,
            query: "bot"
        )
        let existingPresentation = ChatPresentationPreferences(
            repeatCollapseEnabled: true,
            rules: [existingRule]
        )
        var content = try sampleExport().document.content
        content.settings.recentMessagesEnabled = false
        content.settings.localHistoryEnabled = false
        content.settings.localHistoryLimit = 2_000
        content.settings.localHistoryRetentionDays = 90
        content.settings.localHistoryMaxSizeMb = 512
        content.settings.repeatCollapseEnabled = false
        content.channels = SettingsBackupChannels(
            logins: (0..<10).map { "channel\($0)" },
            selectedLogin: "channel7"
        )
        let document = try SettingsBackupCodec.makeDocument(
            content: content,
            appVersion: "android-test",
            createdAt: "2026-08-14T17:31:00Z"
        )

        let plan = SettingsBackupBridge.importPlan(
            document: document,
            existingPresentationPreferences: existingPresentation,
            workspaceCapacity: 8
        )

        #expect(plan.historyPreferences.recentMessagesEnabled == false)
        #expect(plan.historyPreferences.localHistoryEnabled == false)
        #expect(plan.historyPreferences.localHistoryLimit == 2_000)
        #expect(plan.historyPreferences.retentionDays == 90)
        #expect(plan.historyPreferences.maxDatabaseSizeMB == 512)
        #expect(plan.presentationPreferences.repeatCollapseEnabled == false)
        #expect(plan.presentationPreferences.rules == [existingRule])
        #expect(plan.channelLogins == (0..<8).map { "channel\($0)" })
        #expect(plan.selectedChannelLogin == "channel7")
        #expect(plan.droppedChannelCount == 2)
    }

    @Test
    func importPlanNormalizesChannelsBeforeCapacityAndSelection() throws {
        var content = try sampleExport().document.content
        content.channels = SettingsBackupChannels(
            logins: [
                "  Alpha  ",
                "ALPHA",
                "   ",
                "Beta",
                "Gamma",
                "Delta",
            ],
            selectedLogin: "  BETA  "
        )
        let document = try SettingsBackupCodec.makeDocument(
            content: content,
            appVersion: "android-test",
            createdAt: "2026-08-14T17:31:30Z"
        )

        let plan = SettingsBackupBridge.importPlan(
            document: document,
            existingPresentationPreferences: .default,
            workspaceCapacity: 3
        )

        #expect(plan.channelLogins == ["alpha", "beta", "gamma"])
        #expect(plan.selectedChannelLogin == "beta")
        #expect(plan.droppedChannelCount == 1)
    }

    @Test
    func importPlanFallsBackToFirstRetainedChannelWhenSelectionIsDropped() throws {
        var content = try sampleExport().document.content
        content.channels = SettingsBackupChannels(
            logins: ["one", "two", "three"],
            selectedLogin: "three"
        )
        let document = try SettingsBackupCodec.makeDocument(
            content: content,
            appVersion: "android-test",
            createdAt: "2026-08-14T17:32:00Z"
        )

        let plan = SettingsBackupBridge.importPlan(
            document: document,
            existingPresentationPreferences: .default,
            workspaceCapacity: 2
        )

        #expect(plan.channelLogins == ["one", "two"])
        #expect(plan.selectedChannelLogin == "one")
        #expect(plan.droppedChannelCount == 1)
    }

    @Test
    func importPlanReportsPortableContentThatIOSCannotApplyYet() throws {
        var content = try sampleExport().document.content
        content.workspaces = .object([
            .init(key: "schemaVersion", value: .number("2")),
            .init(key: "workspaces", value: .array([])),
        ])
        content.filters = .object([
            .init(key: "schemaVersion", value: .number("1")),
            .init(key: "filters", value: .array([])),
        ])
        content.highlights = .array([.object([]), .object([])])
        content.ignoreRules = .array([.object([])])
        content.commands = .object([
            .init(key: "hello", value: .string("world")),
        ])
        content.favouriteEmotes = ["bttv:one", "ffz:two"]
        let document = try SettingsBackupCodec.makeDocument(
            content: content,
            appVersion: "android-test",
            createdAt: "2026-08-14T17:33:00Z"
        )

        let plan = SettingsBackupBridge.importPlan(
            document: document,
            existingPresentationPreferences: .default
        )

        #expect(plan.unsupportedContent.hasWorkspaceLayout)
        #expect(plan.unsupportedContent.hasFilters)
        #expect(plan.unsupportedContent.highlightCount == 2)
        #expect(plan.unsupportedContent.ignoreRuleCount == 1)
        #expect(plan.unsupportedContent.hasCommands)
        #expect(plan.unsupportedContent.favouriteEmoteCount == 2)
        #expect(plan.unsupportedContent.hasAny)
    }

    private func sampleExport() throws -> SettingsBackupExportResult {
        try SettingsBackupBridge.capture(
            historyPreferences: .default,
            presentationPreferences: .default,
            workspaceSnapshot: .empty,
            appVersion: "0.0.1-test",
            createdAt: "2026-08-14T17:29:00Z"
        )
    }
}
