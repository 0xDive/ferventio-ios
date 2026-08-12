import Foundation

public enum UserCardContext {
    public static let defaultRecentMessageLimit = 20

    public static func messages(
        for author: ChatAuthor,
        in messages: [ChatMessage]
    ) -> [ChatMessage] {
        messages.filter { message in
            if !author.id.isEmpty, !message.author.id.isEmpty {
                return message.author.id == author.id
            }
            return message.author.login.caseInsensitiveCompare(author.login) == .orderedSame
        }
    }

    public static func recentMessages(
        for author: ChatAuthor,
        in messages: [ChatMessage],
        limit: Int = defaultRecentMessageLimit
    ) -> [ChatMessage] {
        guard limit > 0 else {
            return []
        }
        return Array(self.messages(for: author, in: messages).suffix(limit).reversed())
    }

    public static func protectedRoleBadgeSetIDs(for author: ChatAuthor) -> [String] {
        let protectedRoles = ["broadcaster", "moderator", "vip"]
        let badgeSetIDs = Set(author.badges.map(\.setID))
        return protectedRoles.filter(badgeSetIDs.contains)
    }
}
