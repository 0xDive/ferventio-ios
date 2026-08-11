import FerventioDomain
import FerventioNetworking

protocol RecentMessagesLoading: Sendable {
    func load(
        channel: ChatChannel,
        limit: Int
    ) async throws -> TwitchRecentMessagesResult
}

extension TwitchRecentMessagesClient: RecentMessagesLoading {}

struct NoopRecentMessagesLoader: RecentMessagesLoading {
    func load(
        channel: ChatChannel,
        limit: Int
    ) async throws -> TwitchRecentMessagesResult {
        TwitchRecentMessagesResult(messages: [])
    }
}

enum RecentMessagesLoaderFactory {
    static func live() -> any RecentMessagesLoading {
        if let client = try? TwitchRecentMessagesClient() {
            return client
        }
        return NoopRecentMessagesLoader()
    }
}
