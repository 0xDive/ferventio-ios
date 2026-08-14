import CryptoKit
import Foundation

public enum SettingsBackupFormat {
    public static let identifier = "ferventio-settings-backup"
    public static let currentVersion = 2
    public static let maximumFileBytes = 1_048_576
    public static let maximumJSONDepth = 64
}

public enum SettingsBackupError: Error, Equatable, LocalizedError, Sendable {
    case fileTooLarge
    case nestingTooDeep
    case invalidJSON
    case invalidDocument(String)
    case checksumMismatch

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "The settings backup is larger than 1 MiB."
        case .nestingTooDeep:
            return "The settings backup JSON is nested too deeply."
        case .invalidJSON:
            return "The settings backup is not valid JSON."
        case let .invalidDocument(reason):
            return reason
        case .checksumMismatch:
            return "The settings backup checksum does not match its content."
        }
    }
}

public struct SettingsBackupJSONMember: Equatable, Sendable {
    public let key: String
    public let value: SettingsBackupJSONValue

    public init(key: String, value: SettingsBackupJSONValue) {
        self.key = key
        self.value = value
    }
}

public indirect enum SettingsBackupJSONValue: Equatable, Sendable {
    case object([SettingsBackupJSONMember])
    case array([SettingsBackupJSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public static let emptyObject: Self = .object([])
    public static let emptyArray: Self = .array([])
}

public struct SettingsBackupTabTitle: Equatable, Sendable {
    public let channelID: String
    public let title: String

    public init(channelID: String, title: String) {
        self.channelID = channelID
        self.title = title
    }
}

public struct SettingsBackupSettings: Equatable, Sendable {
    public var appLanguage: String
    public var themeMode: String
    public var fontScalePercent: Int
    public var messageDensity: String
    public var showAvatars: Bool
    public var showBadges: Bool
    public var showTimestamps: Bool
    public var nameStyle: String
    public var wrapMessageLines: Bool
    public var showDeletedMessageContent: Bool
    public var showSystemMessages: Bool
    public var mentionColorArgb: Int64
    public var autoScrollEnabled: Bool
    public var repeatCollapseEnabled: Bool
    public var animateEmotes: Bool
    public var emoteScalePercent: Int
    public var betterTtvEnabled: Bool
    public var frankerFaceZEnabled: Bool
    public var sevenTvEnabled: Bool
    public var sendOnEnter: Bool
    public var showComposerEmoteImages: Bool
    public var replyNotificationsEnabled: Bool
    public var autoModNotificationsEnabled: Bool
    public var recentMessagesEnabled: Bool
    public var localHistoryEnabled: Bool
    public var localHistoryLimit: Int
    public var localHistoryRetentionDays: Int
    public var localHistoryMaxSizeMb: Int
    public var userCardTimeoutPresetsSeconds: [Int]
    public var userCardShowBanAction: Bool
    public var userCardModerationActionOrder: [String]

    public init(
        appLanguage: String = "RUSSIAN",
        themeMode: String,
        fontScalePercent: Int,
        messageDensity: String,
        showAvatars: Bool,
        showBadges: Bool,
        showTimestamps: Bool,
        nameStyle: String,
        wrapMessageLines: Bool,
        showDeletedMessageContent: Bool,
        showSystemMessages: Bool = true,
        mentionColorArgb: Int64,
        autoScrollEnabled: Bool,
        repeatCollapseEnabled: Bool = true,
        animateEmotes: Bool,
        emoteScalePercent: Int,
        betterTtvEnabled: Bool,
        frankerFaceZEnabled: Bool,
        sevenTvEnabled: Bool,
        sendOnEnter: Bool,
        showComposerEmoteImages: Bool,
        replyNotificationsEnabled: Bool,
        autoModNotificationsEnabled: Bool,
        recentMessagesEnabled: Bool = false,
        localHistoryEnabled: Bool,
        localHistoryLimit: Int,
        localHistoryRetentionDays: Int,
        localHistoryMaxSizeMb: Int,
        userCardTimeoutPresetsSeconds: [Int],
        userCardShowBanAction: Bool,
        userCardModerationActionOrder: [String]
    ) {
        self.appLanguage = appLanguage
        self.themeMode = themeMode
        self.fontScalePercent = fontScalePercent
        self.messageDensity = messageDensity
        self.showAvatars = showAvatars
        self.showBadges = showBadges
        self.showTimestamps = showTimestamps
        self.nameStyle = nameStyle
        self.wrapMessageLines = wrapMessageLines
        self.showDeletedMessageContent = showDeletedMessageContent
        self.showSystemMessages = showSystemMessages
        self.mentionColorArgb = mentionColorArgb
        self.autoScrollEnabled = autoScrollEnabled
        self.repeatCollapseEnabled = repeatCollapseEnabled
        self.animateEmotes = animateEmotes
        self.emoteScalePercent = emoteScalePercent
        self.betterTtvEnabled = betterTtvEnabled
        self.frankerFaceZEnabled = frankerFaceZEnabled
        self.sevenTvEnabled = sevenTvEnabled
        self.sendOnEnter = sendOnEnter
        self.showComposerEmoteImages = showComposerEmoteImages
        self.replyNotificationsEnabled = replyNotificationsEnabled
        self.autoModNotificationsEnabled = autoModNotificationsEnabled
        self.recentMessagesEnabled = recentMessagesEnabled
        self.localHistoryEnabled = localHistoryEnabled
        self.localHistoryLimit = localHistoryLimit
        self.localHistoryRetentionDays = localHistoryRetentionDays
        self.localHistoryMaxSizeMb = localHistoryMaxSizeMb
        self.userCardTimeoutPresetsSeconds = userCardTimeoutPresetsSeconds
        self.userCardShowBanAction = userCardShowBanAction
        self.userCardModerationActionOrder = userCardModerationActionOrder
    }
}

public struct SettingsBackupChannels: Equatable, Sendable {
    public var logins: [String]
    public var selectedLogin: String?
    public var favouriteChannelIds: [String]
    public var pinnedChannelIds: [String]
    public var recentChannelIds: [String]
    public var tabTitles: [SettingsBackupTabTitle]

    public init(
        logins: [String],
        selectedLogin: String? = nil,
        favouriteChannelIds: [String] = [],
        pinnedChannelIds: [String] = [],
        recentChannelIds: [String] = [],
        tabTitles: [SettingsBackupTabTitle] = []
    ) {
        self.logins = logins
        self.selectedLogin = selectedLogin
        self.favouriteChannelIds = favouriteChannelIds
        self.pinnedChannelIds = pinnedChannelIds
        self.recentChannelIds = recentChannelIds
        self.tabTitles = tabTitles
    }
}

public struct SettingsBackupContent: Equatable, Sendable {
    public var settings: SettingsBackupSettings
    public var channels: SettingsBackupChannels
    public var workspaces: SettingsBackupJSONValue
    public var filters: SettingsBackupJSONValue
    public var highlights: SettingsBackupJSONValue
    public var ignoreRules: SettingsBackupJSONValue
    public var commands: SettingsBackupJSONValue
    public var favouriteEmotes: [String]

    public init(
        settings: SettingsBackupSettings,
        channels: SettingsBackupChannels,
        workspaces: SettingsBackupJSONValue = .null,
        filters: SettingsBackupJSONValue = .emptyObject,
        highlights: SettingsBackupJSONValue = .emptyArray,
        ignoreRules: SettingsBackupJSONValue = .emptyArray,
        commands: SettingsBackupJSONValue = .emptyObject,
        favouriteEmotes: [String] = []
    ) {
        self.settings = settings
        self.channels = channels
        self.workspaces = workspaces
        self.filters = filters
        self.highlights = highlights
        self.ignoreRules = ignoreRules
        self.commands = commands
        self.favouriteEmotes = favouriteEmotes
    }
}

public struct SettingsBackupDocument: Equatable, Sendable {
    public var format: String
    public var formatVersion: Int
    public var createdAt: String
    public var appVersion: String
    public var contentHash: String
    public var content: SettingsBackupContent

    public init(
        format: String = SettingsBackupFormat.identifier,
        formatVersion: Int = SettingsBackupFormat.currentVersion,
        createdAt: String,
        appVersion: String,
        contentHash: String,
        content: SettingsBackupContent
    ) {
        self.format = format
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.contentHash = contentHash
        self.content = content
    }
}

public enum SettingsBackupCodec {
    public static func makeDocument(
        content: SettingsBackupContent,
        appVersion: String,
        createdAt: String,
        formatVersion: Int = SettingsBackupFormat.currentVersion
    ) throws -> SettingsBackupDocument {
        try validate(content)
        guard (1...SettingsBackupFormat.currentVersion).contains(formatVersion) else {
            throw SettingsBackupError.invalidDocument("Unsupported settings backup version: \(formatVersion).")
        }
        try validateDate(createdAt)
        return SettingsBackupDocument(
            formatVersion: formatVersion,
            createdAt: createdAt,
            appVersion: appVersion,
            contentHash: contentHash(content, formatVersion: formatVersion),
            content: content
        )
    }

    public static func encode(_ document: SettingsBackupDocument, pretty: Bool = true) throws -> String {
        try validateDocument(document, verifyChecksum: true)
        let value = documentJSON(document)
        return pretty ? value.prettyJSONString() : value.canonicalJSONString()
    }

    public static func decode(_ raw: String) throws -> SettingsBackupDocument {
        guard raw.utf8.count <= SettingsBackupFormat.maximumFileBytes else {
            throw SettingsBackupError.fileTooLarge
        }
        try requireDepthWithinLimit(raw)

        var parser = OrderedJSONParser(raw)
        let root: SettingsBackupJSONValue
        do {
            root = try parser.parse()
        } catch {
            throw SettingsBackupError.invalidJSON
        }

        var document = try decodeDocument(root)
        if document.formatVersion == 1 {
            document.content.settings.repeatCollapseEnabled = true
        }
        try validateDocument(document, verifyChecksum: true)
        return document
    }

    public static func contentHash(
        _ content: SettingsBackupContent,
        formatVersion: Int = SettingsBackupFormat.currentVersion
    ) -> String {
        let canonical = contentJSON(
            content,
            omitLegacyRepeatCollapse: formatVersion == 1
        ).canonicalJSONString()
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func validateDocument(
        _ document: SettingsBackupDocument,
        verifyChecksum: Bool
    ) throws {
        guard document.format == SettingsBackupFormat.identifier else {
            throw SettingsBackupError.invalidDocument("This file is not a Ferventio settings backup.")
        }
        guard (1...SettingsBackupFormat.currentVersion).contains(document.formatVersion) else {
            throw SettingsBackupError.invalidDocument("Unsupported settings backup version: \(document.formatVersion).")
        }
        try validateDate(document.createdAt)
        try validate(document.content)
        if verifyChecksum,
           document.contentHash != contentHash(document.content, formatVersion: document.formatVersion) {
            throw SettingsBackupError.checksumMismatch
        }
    }

    private static func validate(_ content: SettingsBackupContent) throws {
        let settings = content.settings
        guard ["SYSTEM", "RUSSIAN", "ENGLISH"].contains(settings.appLanguage) else {
            throw SettingsBackupError.invalidDocument("Unknown application language.")
        }
        guard ["LIGHT", "DARK", "AMOLED"].contains(settings.themeMode) else {
            throw SettingsBackupError.invalidDocument("Unknown theme mode.")
        }
        guard (80...150).contains(settings.fontScalePercent) else {
            throw SettingsBackupError.invalidDocument("Font scale is outside the supported range.")
        }
        guard ["COMPACT", "NORMAL", "RELAXED"].contains(settings.messageDensity) else {
            throw SettingsBackupError.invalidDocument("Unknown message density.")
        }
        guard ["DISPLAY_NAME", "LOGIN", "DISPLAY_AND_LOGIN"].contains(settings.nameStyle) else {
            throw SettingsBackupError.invalidDocument("Unknown chat name style.")
        }
        guard (0...Int64(UInt32.max)).contains(settings.mentionColorArgb) else {
            throw SettingsBackupError.invalidDocument("Mention color is invalid.")
        }
        guard (75...200).contains(settings.emoteScalePercent) else {
            throw SettingsBackupError.invalidDocument("Emote scale is outside the supported range.")
        }
        guard (100...5_000).contains(settings.localHistoryLimit) else {
            throw SettingsBackupError.invalidDocument("Local history limit is invalid.")
        }
        guard (0...365).contains(settings.localHistoryRetentionDays) else {
            throw SettingsBackupError.invalidDocument("Local history retention is invalid.")
        }
        guard (0...1_024).contains(settings.localHistoryMaxSizeMb) else {
            throw SettingsBackupError.invalidDocument("Local history size limit is invalid.")
        }
        guard settings.userCardTimeoutPresetsSeconds.count <= 10 else {
            throw SettingsBackupError.invalidDocument("Too many timeout presets.")
        }
        guard settings.userCardModerationActionOrder.count <= 32 else {
            throw SettingsBackupError.invalidDocument("Moderation action order is too long.")
        }

        let channels = content.channels
        guard channels.logins.count <= 20 else {
            throw SettingsBackupError.invalidDocument("The backup contains more than 20 channels.")
        }
        let loginRegex = try! NSRegularExpression(pattern: "^[A-Za-z0-9_]{1,25}$")
        guard channels.logins.allSatisfy({ login in
            let range = NSRange(login.startIndex..<login.endIndex, in: login)
            return loginRegex.firstMatch(in: login, range: range)?.range == range
        }) else {
            throw SettingsBackupError.invalidDocument("The backup contains an invalid Twitch login.")
        }
        guard Set(channels.logins.map { $0.lowercased() }).count == channels.logins.count else {
            throw SettingsBackupError.invalidDocument("The backup contains duplicate channels.")
        }
        guard channels.favouriteChannelIds.count <= 20,
              channels.pinnedChannelIds.count <= 20,
              channels.recentChannelIds.count <= 20 else {
            throw SettingsBackupError.invalidDocument("The backup contains too many channel references.")
        }
        guard channels.tabTitles.count <= 20,
              channels.tabTitles.allSatisfy({ $0.title.utf16.count <= 32 }) else {
            throw SettingsBackupError.invalidDocument("The backup contains invalid channel tab titles.")
        }

        if case let .object(workspaceMembers) = content.workspaces {
            if let schema = workspaceMembers.lastValue(for: "schemaVersion")?.intValue,
               !(1...2).contains(schema) {
                throw SettingsBackupError.invalidDocument("Unsupported workspace schema version: \(schema).")
            }
            if case let .array(workspaces)? = workspaceMembers.lastValue(for: "workspaces"), workspaces.count > 10 {
                throw SettingsBackupError.invalidDocument("The backup contains too many workspaces.")
            }
        } else if content.workspaces != .null {
            throw SettingsBackupError.invalidDocument("Workspaces must be a JSON object or null.")
        }

        if case let .array(highlights) = content.highlights, highlights.count > 100 {
            throw SettingsBackupError.invalidDocument("The backup contains too many highlight rules.")
        }
        if case let .array(ignoreRules) = content.ignoreRules, ignoreRules.count > 100 {
            throw SettingsBackupError.invalidDocument("The backup contains too many ignore rules.")
        }
        guard content.favouriteEmotes.count <= 2_000,
              content.favouriteEmotes.allSatisfy({ (1...160).contains($0.utf16.count) }) else {
            throw SettingsBackupError.invalidDocument("The favourite emote list is invalid.")
        }
    }

    private static func validateDate(_ value: String) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil {
            return
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard formatter.date(from: value) != nil else {
            throw SettingsBackupError.invalidDocument("The settings backup creation date is invalid.")
        }
    }

    private static func requireDepthWithinLimit(_ raw: String) throws {
        var depth = 0
        var inString = false
        var escaping = false

        for scalar in raw.unicodeScalars {
            let character = scalar.value
            if inString {
                if escaping {
                    escaping = false
                } else if character == 0x5C {
                    escaping = true
                } else if character == 0x22 {
                    inString = false
                }
                continue
            }

            switch character {
            case 0x22:
                inString = true
            case 0x7B, 0x5B:
                depth += 1
                if depth > SettingsBackupFormat.maximumJSONDepth {
                    throw SettingsBackupError.nestingTooDeep
                }
            case 0x7D, 0x5D:
                if depth > 0 { depth -= 1 }
            default:
                break
            }
        }
    }

    private static func decodeDocument(_ root: SettingsBackupJSONValue) throws -> SettingsBackupDocument {
        let object = try root.requiredObject("Settings backup root")
        let format = try object.optionalString("format") ?? SettingsBackupFormat.identifier
        let formatVersion = try object.optionalInt("formatVersion") ?? SettingsBackupFormat.currentVersion
        let createdAt = try object.requiredString("createdAt")
        let appVersion = try object.requiredString("appVersion")
        let contentHash = try object.requiredString("contentHash")
        let contentValue = try object.requiredValue("content")
        let content = try decodeContent(contentValue)
        return SettingsBackupDocument(
            format: format,
            formatVersion: formatVersion,
            createdAt: createdAt,
            appVersion: appVersion,
            contentHash: contentHash,
            content: content
        )
    }

    private static func decodeContent(_ value: SettingsBackupJSONValue) throws -> SettingsBackupContent {
        let object = try value.requiredObject("Settings backup content")
        let settings = try decodeSettings(object.requiredValue("settings"))
        let channels = try decodeChannels(object.requiredValue("channels"))
        return SettingsBackupContent(
            settings: settings,
            channels: channels,
            workspaces: object.lastValue(for: "workspaces") ?? .null,
            filters: object.lastValue(for: "filters") ?? .emptyObject,
            highlights: object.lastValue(for: "highlights") ?? .emptyArray,
            ignoreRules: object.lastValue(for: "ignoreRules") ?? .emptyArray,
            commands: object.lastValue(for: "commands") ?? .emptyObject,
            favouriteEmotes: try object.optionalStringArray("favouriteEmotes") ?? []
        )
    }

    private static func decodeSettings(_ value: SettingsBackupJSONValue) throws -> SettingsBackupSettings {
        let object = try value.requiredObject("Backup settings")
        return SettingsBackupSettings(
            appLanguage: try object.optionalString("appLanguage") ?? "RUSSIAN",
            themeMode: try object.requiredString("themeMode"),
            fontScalePercent: try object.requiredInt("fontScalePercent"),
            messageDensity: try object.requiredString("messageDensity"),
            showAvatars: try object.requiredBool("showAvatars"),
            showBadges: try object.requiredBool("showBadges"),
            showTimestamps: try object.requiredBool("showTimestamps"),
            nameStyle: try object.requiredString("nameStyle"),
            wrapMessageLines: try object.requiredBool("wrapMessageLines"),
            showDeletedMessageContent: try object.requiredBool("showDeletedMessageContent"),
            showSystemMessages: try object.optionalBool("showSystemMessages") ?? true,
            mentionColorArgb: try object.requiredInt64("mentionColorArgb"),
            autoScrollEnabled: try object.requiredBool("autoScrollEnabled"),
            repeatCollapseEnabled: try object.optionalBool("repeatCollapseEnabled") ?? true,
            animateEmotes: try object.requiredBool("animateEmotes"),
            emoteScalePercent: try object.requiredInt("emoteScalePercent"),
            betterTtvEnabled: try object.requiredBool("betterTtvEnabled"),
            frankerFaceZEnabled: try object.requiredBool("frankerFaceZEnabled"),
            sevenTvEnabled: try object.requiredBool("sevenTvEnabled"),
            sendOnEnter: try object.requiredBool("sendOnEnter"),
            showComposerEmoteImages: try object.requiredBool("showComposerEmoteImages"),
            replyNotificationsEnabled: try object.requiredBool("replyNotificationsEnabled"),
            autoModNotificationsEnabled: try object.requiredBool("autoModNotificationsEnabled"),
            recentMessagesEnabled: try object.optionalBool("recentMessagesEnabled") ?? false,
            localHistoryEnabled: try object.requiredBool("localHistoryEnabled"),
            localHistoryLimit: try object.requiredInt("localHistoryLimit"),
            localHistoryRetentionDays: try object.requiredInt("localHistoryRetentionDays"),
            localHistoryMaxSizeMb: try object.requiredInt("localHistoryMaxSizeMb"),
            userCardTimeoutPresetsSeconds: try object.requiredIntArray("userCardTimeoutPresetsSeconds"),
            userCardShowBanAction: try object.requiredBool("userCardShowBanAction"),
            userCardModerationActionOrder: try object.requiredStringArray("userCardModerationActionOrder")
        )
    }

    private static func decodeChannels(_ value: SettingsBackupJSONValue) throws -> SettingsBackupChannels {
        let object = try value.requiredObject("Backup channels")
        let tabTitles: [SettingsBackupTabTitle]
        if let titlesValue = object.lastValue(for: "tabTitles") {
            let titlesObject = try titlesValue.requiredObject("Channel tab titles")
            tabTitles = try titlesObject.map { member in
                guard case let .string(title) = member.value else {
                    throw SettingsBackupError.invalidDocument("Channel tab title must be a string.")
                }
                return SettingsBackupTabTitle(channelID: member.key, title: title)
            }
        } else {
            tabTitles = []
        }

        return SettingsBackupChannels(
            logins: try object.requiredStringArray("logins"),
            selectedLogin: try object.optionalString("selectedLogin"),
            favouriteChannelIds: try object.optionalStringArray("favouriteChannelIds") ?? [],
            pinnedChannelIds: try object.optionalStringArray("pinnedChannelIds") ?? [],
            recentChannelIds: try object.optionalStringArray("recentChannelIds") ?? [],
            tabTitles: tabTitles
        )
    }

    private static func documentJSON(_ document: SettingsBackupDocument) -> SettingsBackupJSONValue {
        .object([
            .init(key: "format", value: .string(document.format)),
            .init(key: "formatVersion", value: .number(String(document.formatVersion))),
            .init(key: "createdAt", value: .string(document.createdAt)),
            .init(key: "appVersion", value: .string(document.appVersion)),
            .init(key: "contentHash", value: .string(document.contentHash)),
            .init(key: "content", value: contentJSON(document.content, omitLegacyRepeatCollapse: false)),
        ])
    }

    private static func contentJSON(
        _ content: SettingsBackupContent,
        omitLegacyRepeatCollapse: Bool
    ) -> SettingsBackupJSONValue {
        .object([
            .init(
                key: "settings",
                value: settingsJSON(
                    content.settings,
                    includeRepeatCollapse: !omitLegacyRepeatCollapse
                )
            ),
            .init(key: "channels", value: channelsJSON(content.channels)),
            .init(key: "workspaces", value: content.workspaces),
            .init(key: "filters", value: content.filters),
            .init(key: "highlights", value: content.highlights),
            .init(key: "ignoreRules", value: content.ignoreRules),
            .init(key: "commands", value: content.commands),
            .init(key: "favouriteEmotes", value: .array(content.favouriteEmotes.map(SettingsBackupJSONValue.string))),
        ])
    }

    private static func settingsJSON(
        _ settings: SettingsBackupSettings,
        includeRepeatCollapse: Bool
    ) -> SettingsBackupJSONValue {
        var members: [SettingsBackupJSONMember] = [
            .init(key: "appLanguage", value: .string(settings.appLanguage)),
            .init(key: "themeMode", value: .string(settings.themeMode)),
            .init(key: "fontScalePercent", value: .number(String(settings.fontScalePercent))),
            .init(key: "messageDensity", value: .string(settings.messageDensity)),
            .init(key: "showAvatars", value: .bool(settings.showAvatars)),
            .init(key: "showBadges", value: .bool(settings.showBadges)),
            .init(key: "showTimestamps", value: .bool(settings.showTimestamps)),
            .init(key: "nameStyle", value: .string(settings.nameStyle)),
            .init(key: "wrapMessageLines", value: .bool(settings.wrapMessageLines)),
            .init(key: "showDeletedMessageContent", value: .bool(settings.showDeletedMessageContent)),
            .init(key: "showSystemMessages", value: .bool(settings.showSystemMessages)),
            .init(key: "mentionColorArgb", value: .number(String(settings.mentionColorArgb))),
            .init(key: "autoScrollEnabled", value: .bool(settings.autoScrollEnabled)),
        ]
        if includeRepeatCollapse {
            members.append(.init(key: "repeatCollapseEnabled", value: .bool(settings.repeatCollapseEnabled)))
        }
        members.append(contentsOf: [
            .init(key: "animateEmotes", value: .bool(settings.animateEmotes)),
            .init(key: "emoteScalePercent", value: .number(String(settings.emoteScalePercent))),
            .init(key: "betterTtvEnabled", value: .bool(settings.betterTtvEnabled)),
            .init(key: "frankerFaceZEnabled", value: .bool(settings.frankerFaceZEnabled)),
            .init(key: "sevenTvEnabled", value: .bool(settings.sevenTvEnabled)),
            .init(key: "sendOnEnter", value: .bool(settings.sendOnEnter)),
            .init(key: "showComposerEmoteImages", value: .bool(settings.showComposerEmoteImages)),
            .init(key: "replyNotificationsEnabled", value: .bool(settings.replyNotificationsEnabled)),
            .init(key: "autoModNotificationsEnabled", value: .bool(settings.autoModNotificationsEnabled)),
            .init(key: "recentMessagesEnabled", value: .bool(settings.recentMessagesEnabled)),
            .init(key: "localHistoryEnabled", value: .bool(settings.localHistoryEnabled)),
            .init(key: "localHistoryLimit", value: .number(String(settings.localHistoryLimit))),
            .init(key: "localHistoryRetentionDays", value: .number(String(settings.localHistoryRetentionDays))),
            .init(key: "localHistoryMaxSizeMb", value: .number(String(settings.localHistoryMaxSizeMb))),
            .init(key: "userCardTimeoutPresetsSeconds", value: .array(settings.userCardTimeoutPresetsSeconds.map { .number(String($0)) })),
            .init(key: "userCardShowBanAction", value: .bool(settings.userCardShowBanAction)),
            .init(key: "userCardModerationActionOrder", value: .array(settings.userCardModerationActionOrder.map(SettingsBackupJSONValue.string))),
        ])
        return .object(members)
    }

    private static func channelsJSON(_ channels: SettingsBackupChannels) -> SettingsBackupJSONValue {
        var members: [SettingsBackupJSONMember] = [
            .init(key: "logins", value: .array(channels.logins.map(SettingsBackupJSONValue.string))),
        ]
        if let selectedLogin = channels.selectedLogin {
            members.append(.init(key: "selectedLogin", value: .string(selectedLogin)))
        }
        members.append(contentsOf: [
            .init(key: "favouriteChannelIds", value: .array(channels.favouriteChannelIds.map(SettingsBackupJSONValue.string))),
            .init(key: "pinnedChannelIds", value: .array(channels.pinnedChannelIds.map(SettingsBackupJSONValue.string))),
            .init(key: "recentChannelIds", value: .array(channels.recentChannelIds.map(SettingsBackupJSONValue.string))),
            .init(
                key: "tabTitles",
                value: .object(channels.tabTitles.map { .init(key: $0.channelID, value: .string($0.title)) })
            ),
        ])
        return .object(members)
    }
}

private extension Array where Element == SettingsBackupJSONMember {
    func lastValue(for key: String) -> SettingsBackupJSONValue? {
        last(where: { $0.key == key })?.value
    }

    func requiredValue(_ key: String) throws -> SettingsBackupJSONValue {
        guard let value = lastValue(for: key) else {
            throw SettingsBackupError.invalidDocument("Missing required backup field: \(key).")
        }
        return value
    }

    func requiredString(_ key: String) throws -> String {
        guard case let .string(value) = try requiredValue(key) else {
            throw SettingsBackupError.invalidDocument("Backup field \(key) must be a string.")
        }
        return value
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = lastValue(for: key) else { return nil }
        if value == .null { return nil }
        guard case let .string(string) = value else {
            throw SettingsBackupError.invalidDocument("Backup field \(key) must be a string.")
        }
        return string
    }

    func requiredBool(_ key: String) throws -> Bool {
        guard case let .bool(value) = try requiredValue(key) else {
            throw SettingsBackupError.invalidDocument("Backup field \(key) must be a boolean.")
        }
        return value
    }

    func optionalBool(_ key: String) throws -> Bool? {
        guard let value = lastValue(for: key) else { return nil }
        guard case let .bool(boolean) = value else {
            throw SettingsBackupError.invalidDocument("Backup field \(key) must be a boolean.")
        }
        return boolean
    }

    func requiredInt(_ key: String) throws -> Int {
        guard let value = try requiredValue(key).intValue else {
            throw SettingsBackupError.invalidDocument("Backup field \(key) must be an integer.")
        }
        return value
    }

    func optionalInt(_ key: String) throws -> Int? {
        guard let value = lastValue(for: key) else { return nil }
        guard let integer = value.intValue else {
            throw SettingsBackupError.invalidDocument("Backup field \(key) must be an integer.")
        }
        return integer
    }

    func requiredInt64(_ key: String) throws -> Int64 {
        guard case let .number(raw) = try requiredValue(key), let value = Int64(raw) else {
            throw SettingsBackupError.invalidDocument("Backup field \(key) must be an integer.")
        }
        return value
    }

    func requiredStringArray(_ key: String) throws -> [String] {
        guard case let .array(values) = try requiredValue(key) else {
            throw SettingsBackupError.invalidDocument("Backup field \(key) must be an array.")
        }
        return try values.map { value in
            guard case let .string(string) = value else {
                throw SettingsBackupError.invalidDocument("Backup field \(key) must contain strings.")
            }
            return string
        }
    }

    func optionalStringArray(_ key: String) throws -> [String]? {
        guard lastValue(for: key) != nil else { return nil }
        return try requiredStringArray(key)
    }

    func requiredIntArray(_ key: String) throws -> [Int] {
        guard case let .array(values) = try requiredValue(key) else {
            throw SettingsBackupError.invalidDocument("Backup field \(key) must be an array.")
        }
        return try values.map { value in
            guard let integer = value.intValue else {
                throw SettingsBackupError.invalidDocument("Backup field \(key) must contain integers.")
            }
            return integer
        }
    }
}

private extension SettingsBackupJSONValue {
    var intValue: Int? {
        guard case let .number(raw) = self else { return nil }
        return Int(raw)
    }

    func requiredObject(_ label: String) throws -> [SettingsBackupJSONMember] {
        guard case let .object(members) = self else {
            throw SettingsBackupError.invalidDocument("\(label) must be a JSON object.")
        }
        return members
    }

    func canonicalJSONString() -> String {
        switch self {
        case let .object(members):
            return "{" + members.map { member in
                jsonQuoted(member.key) + ":" + member.value.canonicalJSONString()
            }.joined(separator: ",") + "}"
        case let .array(values):
            return "[" + values.map { $0.canonicalJSONString() }.joined(separator: ",") + "]"
        case let .string(value):
            return jsonQuoted(value)
        case let .number(value):
            return value
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }

    func prettyJSONString(level: Int = 0) -> String {
        let indent = String(repeating: "  ", count: level)
        let childIndent = String(repeating: "  ", count: level + 1)
        switch self {
        case let .object(members):
            guard !members.isEmpty else { return "{}" }
            let body = members.map { member in
                childIndent + jsonQuoted(member.key) + ": " + member.value.prettyJSONString(level: level + 1)
            }.joined(separator: ",\n")
            return "{\n" + body + "\n" + indent + "}"
        case let .array(values):
            guard !values.isEmpty else { return "[]" }
            let body = values.map { childIndent + $0.prettyJSONString(level: level + 1) }.joined(separator: ",\n")
            return "[\n" + body + "\n" + indent + "]"
        case .string, .number, .bool, .null:
            return canonicalJSONString()
        }
    }
}

private func jsonQuoted(_ value: String) -> String {
    var result = "\""
    result.reserveCapacity(value.utf8.count + 2)
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x22: result += "\\\""
        case 0x5C: result += "\\\\"
        case 0x08: result += "\\b"
        case 0x0C: result += "\\f"
        case 0x0A: result += "\\n"
        case 0x0D: result += "\\r"
        case 0x09: result += "\\t"
        case 0x00...0x1F:
            result += String(format: "\\u%04x", scalar.value)
        default:
            result.unicodeScalars.append(scalar)
        }
    }
    result += "\""
    return result
}

private struct OrderedJSONParser {
    private let bytes: [UInt8]
    private var index = 0

    init(_ raw: String) {
        bytes = Array(raw.utf8)
    }

    mutating func parse() throws -> SettingsBackupJSONValue {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard index == bytes.count else { throw SettingsBackupError.invalidJSON }
        return value
    }

    private mutating func parseValue() throws -> SettingsBackupJSONValue {
        skipWhitespace()
        guard index < bytes.count else { throw SettingsBackupError.invalidJSON }
        switch bytes[index] {
        case 0x7B: return try parseObject()
        case 0x5B: return try parseArray()
        case 0x22: return .string(try parseString())
        case 0x74:
            try consumeLiteral("true")
            return .bool(true)
        case 0x66:
            try consumeLiteral("false")
            return .bool(false)
        case 0x6E:
            try consumeLiteral("null")
            return .null
        case 0x2D, 0x30...0x39:
            return .number(try parseNumber())
        default:
            throw SettingsBackupError.invalidJSON
        }
    }

    private mutating func parseObject() throws -> SettingsBackupJSONValue {
        index += 1
        skipWhitespace()
        var members: [SettingsBackupJSONMember] = []
        if consumeIf(0x7D) { return .object(members) }
        while true {
            guard index < bytes.count, bytes[index] == 0x22 else { throw SettingsBackupError.invalidJSON }
            let key = try parseString()
            skipWhitespace()
            guard consumeIf(0x3A) else { throw SettingsBackupError.invalidJSON }
            let value = try parseValue()
            members.append(.init(key: key, value: value))
            skipWhitespace()
            if consumeIf(0x7D) { return .object(members) }
            guard consumeIf(0x2C) else { throw SettingsBackupError.invalidJSON }
            skipWhitespace()
        }
    }

    private mutating func parseArray() throws -> SettingsBackupJSONValue {
        index += 1
        skipWhitespace()
        var values: [SettingsBackupJSONValue] = []
        if consumeIf(0x5D) { return .array(values) }
        while true {
            values.append(try parseValue())
            skipWhitespace()
            if consumeIf(0x5D) { return .array(values) }
            guard consumeIf(0x2C) else { throw SettingsBackupError.invalidJSON }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws -> String {
        let start = index
        index += 1
        var escaping = false
        while index < bytes.count {
            let byte = bytes[index]
            if escaping {
                escaping = false
                index += 1
                continue
            }
            if byte == 0x5C {
                escaping = true
                index += 1
                continue
            }
            if byte == 0x22 {
                index += 1
                let data = Data(bytes[start..<index])
                guard let value = try? JSONDecoder().decode(String.self, from: data) else {
                    throw SettingsBackupError.invalidJSON
                }
                return value
            }
            if byte < 0x20 { throw SettingsBackupError.invalidJSON }
            index += 1
        }
        throw SettingsBackupError.invalidJSON
    }

    private mutating func parseNumber() throws -> String {
        let start = index
        if consumeIf(0x2D), index >= bytes.count { throw SettingsBackupError.invalidJSON }
        if consumeIf(0x30) {
            if index < bytes.count, (0x30...0x39).contains(bytes[index]) {
                throw SettingsBackupError.invalidJSON
            }
        } else {
            guard index < bytes.count, (0x31...0x39).contains(bytes[index]) else {
                throw SettingsBackupError.invalidJSON
            }
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
        }
        if consumeIf(0x2E) {
            guard index < bytes.count, (0x30...0x39).contains(bytes[index]) else {
                throw SettingsBackupError.invalidJSON
            }
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
            index += 1
            if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
            guard index < bytes.count, (0x30...0x39).contains(bytes[index]) else {
                throw SettingsBackupError.invalidJSON
            }
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func consumeLiteral(_ literal: StaticString) throws {
        let expected = Array(String(describing: literal).utf8)
        guard index + expected.count <= bytes.count,
              Array(bytes[index..<(index + expected.count)]) == expected else {
            throw SettingsBackupError.invalidJSON
        }
        index += expected.count
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
            index += 1
        }
    }

    private mutating func consumeIf(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
}
