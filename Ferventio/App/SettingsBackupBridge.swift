import Foundation
import FerventioSupport

struct SettingsBackupUnsupportedContent: Equatable, Sendable {
    let hasWorkspaceLayout: Bool
    let hasFilters: Bool
    let highlightCount: Int
    let ignoreRuleCount: Int
    let hasCommands: Bool
    let favouriteEmoteCount: Int

    var hasAny: Bool {
        hasWorkspaceLayout
            || hasFilters
            || highlightCount > 0
            || ignoreRuleCount > 0
            || hasCommands
            || favouriteEmoteCount > 0
    }
}

struct SettingsBackupExportResult: Equatable, Sendable {
    let document: SettingsBackupDocument
    let omittedPresentationRuleCount: Int
}

struct SettingsBackupImportPlan: Equatable, Sendable {
    let historyPreferences: ChatHistoryPreferences
    let presentationPreferences: ChatPresentationPreferences
    let channelLogins: [String]
    let selectedChannelLogin: String?
    let droppedChannelCount: Int
    let unsupportedContent: SettingsBackupUnsupportedContent
}

enum SettingsBackupBridge {
    static func capture(
        historyPreferences: ChatHistoryPreferences,
        presentationPreferences: ChatPresentationPreferences,
        workspaceSnapshot: ChatWorkspaceRegistrySnapshot,
        appVersion: String,
        createdAt: String
    ) throws -> SettingsBackupExportResult {
        let channels = workspaceSnapshot.workspaces.map(\.login)
        let selectedLogin = workspaceSnapshot.activeWorkspaceID.flatMap { activeID in
            workspaceSnapshot.workspaces.first(where: { $0.id == activeID })?.login
        }
        let content = SettingsBackupContent(
            settings: androidCompatibleSettings(
                historyPreferences: historyPreferences,
                presentationPreferences: presentationPreferences
            ),
            channels: SettingsBackupChannels(
                logins: channels,
                selectedLogin: selectedLogin
            )
        )
        let document = try SettingsBackupCodec.makeDocument(
            content: content,
            appVersion: appVersion,
            createdAt: createdAt
        )
        return SettingsBackupExportResult(
            document: document,
            omittedPresentationRuleCount: presentationPreferences.rules.count
        )
    }

    static func encode(
        _ export: SettingsBackupExportResult,
        pretty: Bool = true
    ) throws -> String {
        try SettingsBackupCodec.encode(export.document, pretty: pretty)
    }

    static func importPlan(
        raw: String,
        existingPresentationPreferences: ChatPresentationPreferences,
        workspaceCapacity: Int = ChatWorkspaceRegistryStore.maximumWorkspaces
    ) throws -> SettingsBackupImportPlan {
        let document = try SettingsBackupCodec.decode(raw)
        return importPlan(
            document: document,
            existingPresentationPreferences: existingPresentationPreferences,
            workspaceCapacity: workspaceCapacity
        )
    }

    static func importPlan(
        document: SettingsBackupDocument,
        existingPresentationPreferences: ChatPresentationPreferences,
        workspaceCapacity: Int = ChatWorkspaceRegistryStore.maximumWorkspaces
    ) -> SettingsBackupImportPlan {
        let settings = document.content.settings
        let channels = document.content.channels
        let capacity = max(0, workspaceCapacity)
        let normalizedLogins = normalizedChannelLogins(channels.logins)
        let retainedLogins = Array(normalizedLogins.prefix(capacity))
        let requestedSelection = channels.selectedLogin.flatMap(
            ChatWorkspaceRegistryStore.normalizedLogin
        )
        let selectedLogin = requestedSelection.flatMap { selected in
            retainedLogins.first(where: { $0 == selected })
        } ?? retainedLogins.first

        return SettingsBackupImportPlan(
            historyPreferences: ChatHistoryPreferences(
                recentMessagesEnabled: settings.recentMessagesEnabled,
                localHistoryEnabled: settings.localHistoryEnabled,
                localHistoryLimit: settings.localHistoryLimit,
                retentionDays: settings.localHistoryRetentionDays,
                maxDatabaseSizeMB: settings.localHistoryMaxSizeMb
            ),
            presentationPreferences: ChatPresentationPreferences(
                repeatCollapseEnabled: settings.repeatCollapseEnabled,
                rules: existingPresentationPreferences.rules
            ),
            channelLogins: retainedLogins,
            selectedChannelLogin: selectedLogin,
            droppedChannelCount: max(0, normalizedLogins.count - retainedLogins.count),
            unsupportedContent: unsupportedContent(in: document.content)
        )
    }

    private static func normalizedChannelLogins(_ rawLogins: [String]) -> [String] {
        var seenLogins = Set<String>()
        var normalizedLogins: [String] = []
        normalizedLogins.reserveCapacity(rawLogins.count)

        for rawLogin in rawLogins {
            guard let login = ChatWorkspaceRegistryStore.normalizedLogin(rawLogin),
                  seenLogins.insert(login).inserted else {
                continue
            }
            normalizedLogins.append(login)
        }
        return normalizedLogins
    }

    private static func androidCompatibleSettings(
        historyPreferences: ChatHistoryPreferences,
        presentationPreferences: ChatPresentationPreferences
    ) -> SettingsBackupSettings {
        // Android v2 requires a complete settings object. Values below describe the
        // current fixed iOS behavior where possible and otherwise use Android's
        // defaults. Import on iOS only applies the subset represented by the plan.
        SettingsBackupSettings(
            appLanguage: "SYSTEM",
            themeMode: "DARK",
            fontScalePercent: 100,
            messageDensity: "NORMAL",
            showAvatars: false,
            showBadges: true,
            showTimestamps: false,
            nameStyle: "DISPLAY_NAME",
            wrapMessageLines: true,
            showDeletedMessageContent: false,
            showSystemMessages: true,
            mentionColorArgb: 0xFFFFC857,
            autoScrollEnabled: true,
            repeatCollapseEnabled: presentationPreferences.repeatCollapseEnabled,
            animateEmotes: true,
            emoteScalePercent: 100,
            betterTtvEnabled: true,
            frankerFaceZEnabled: true,
            sevenTvEnabled: true,
            sendOnEnter: true,
            showComposerEmoteImages: false,
            replyNotificationsEnabled: false,
            autoModNotificationsEnabled: false,
            recentMessagesEnabled: historyPreferences.recentMessagesEnabled,
            localHistoryEnabled: historyPreferences.localHistoryEnabled,
            localHistoryLimit: historyPreferences.localHistoryLimit,
            localHistoryRetentionDays: historyPreferences.retentionDays,
            localHistoryMaxSizeMb: historyPreferences.maxDatabaseSizeMB,
            userCardTimeoutPresetsSeconds: [10, 60, 600, 3_600, 86_400],
            userCardShowBanAction: true,
            userCardModerationActionOrder: [
                "timeout:10",
                "timeout:60",
                "timeout:600",
                "timeout:3600",
                "timeout:86400",
                "warn",
                "ban",
                "unban",
            ]
        )
    }

    private static func unsupportedContent(
        in content: SettingsBackupContent
    ) -> SettingsBackupUnsupportedContent {
        SettingsBackupUnsupportedContent(
            hasWorkspaceLayout: content.workspaces != .null,
            hasFilters: content.filters != .emptyObject,
            highlightCount: content.highlights.arrayCount ?? 0,
            ignoreRuleCount: content.ignoreRules.arrayCount ?? 0,
            hasCommands: content.commands != .emptyObject,
            favouriteEmoteCount: content.favouriteEmotes.count
        )
    }
}

private extension SettingsBackupJSONValue {
    var arrayCount: Int? {
        guard case let .array(values) = self else {
            return nil
        }
        return values.count
    }
}
