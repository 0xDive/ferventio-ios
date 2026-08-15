import Foundation
import FerventioDomain
import FerventioNetworking
import FerventioSupport

protocol PushRegistering: Sendable {
    func register(
        deviceToken: Data,
        channelLogins: [String],
        preferences: PushNotificationPreferences,
        grant: AuthenticationGrant
    ) async throws
    func unregister() async throws
    func selfTest() async throws
}

struct PushRegistrationService: PushRegistering, Sendable {
    private let client: BackendPushRegistrationClient
    private let identityStore: DeviceIdentityStore
    private let twitchBootstrap: any TwitchBootstrapping
    private let appVersion: String

    init(
        client: BackendPushRegistrationClient,
        identityStore: DeviceIdentityStore,
        twitchBootstrap: any TwitchBootstrapping,
        appVersion: String
    ) {
        self.client = client
        self.identityStore = identityStore
        self.twitchBootstrap = twitchBootstrap
        self.appVersion = appVersion
    }

    static func live(configuration: AppConfiguration = .live) -> PushRegistrationService {
        let keychain = KeychainStore(service: configuration.keychainService)
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
        return PushRegistrationService(
            client: BackendPushRegistrationClient(baseURL: configuration.backendURL),
            identityStore: DeviceIdentityStore(store: keychain),
            twitchBootstrap: TwitchBootstrapService(),
            appVersion: version
        )
    }

    func register(
        deviceToken: Data,
        channelLogins: [String],
        preferences: PushNotificationPreferences,
        grant: AuthenticationGrant
    ) async throws {
        let identity = try identityStore.loadOrCreate()
        let channelIDs = try await resolveChannelIDs(
            logins: channelLogins,
            grant: grant
        )
        let registration = BackendAPNsRegistration(
            deviceToken: deviceToken.hexadecimalString,
            appVersion: appVersion,
            channelIDs: channelIDs,
            // The backend intersects this list with channels Twitch currently says
            // the signed-in user moderates, so client assertions cannot grant rights.
            moderatorChannelIDs: channelIDs,
            notificationRules: preferences.backendRules
        )
        try await client.registerAPNs(registration, device: identity)
    }

    func unregister() async throws {
        let identity = try identityStore.loadOrCreate()
        try await client.delete(device: identity)
    }

    func selfTest() async throws {
        let identity = try identityStore.loadOrCreate()
        try await client.selfTest(device: identity)
    }

    private func resolveChannelIDs(
        logins: [String],
        grant: AuthenticationGrant
    ) async throws -> [String] {
        var seenLogins = Set<String>()
        var seenIDs = Set<String>()
        var result: [String] = []

        for rawLogin in logins {
            let login = rawLogin.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !login.isEmpty, seenLogins.insert(login).inserted else {
                continue
            }
            let channel = try await twitchBootstrap.resolveChannel(
                login: login,
                for: grant
            )
            let channelID = channel.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !channelID.isEmpty, seenIDs.insert(channelID).inserted else {
                continue
            }
            result.append(channelID)
        }
        return result
    }
}

private extension Data {
    var hexadecimalString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
