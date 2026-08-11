import FerventioDomain
import FerventioNetworking
import Observation

protocol ChatBadgeLoading: Sendable {
    func getGlobalBadges(clientID: String, accessToken: String) async throws -> [ChatBadgeAsset]
    func getChannelBadges(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async throws -> [ChatBadgeAsset]
}

extension TwitchChatAssetsAPIClient: ChatBadgeLoading {}

@MainActor
@Observable
final class ChatAssetStore {
    private(set) var badgeAssets: [String: ChatBadgeAsset] = [:]
    private(set) var isLoadingBadges = false

    @ObservationIgnored private let badges: any ChatBadgeLoading
    @ObservationIgnored private var loadGeneration = 0

    init(badges: (any ChatBadgeLoading)? = nil) {
        self.badges = badges ?? TwitchChatAssetsAPIClient()
    }

    func loadBadges(
        clientID: String,
        accessToken: String,
        broadcasterID: String
    ) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoadingBadges = true
        defer {
            if loadGeneration == generation {
                isLoadingBadges = false
            }
        }

        let global = (try? await badges.getGlobalBadges(
            clientID: clientID,
            accessToken: accessToken
        )) ?? []
        guard loadGeneration == generation else {
            return
        }

        let channel = (try? await badges.getChannelBadges(
            clientID: clientID,
            accessToken: accessToken,
            broadcasterID: broadcasterID
        )) ?? []
        guard loadGeneration == generation else {
            return
        }

        var merged = Dictionary(uniqueKeysWithValues: global.map { ($0.id, $0) })
        for asset in channel {
            merged[asset.id] = asset
        }
        badgeAssets = merged
    }

    func reset() {
        loadGeneration &+= 1
        badgeAssets.removeAll(keepingCapacity: false)
        isLoadingBadges = false
    }
}
