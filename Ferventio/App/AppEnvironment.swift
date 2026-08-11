import Foundation
import FerventioDomain
import Observation

@MainActor
@Observable
final class AppEnvironment {
    var state: AppState = .launching
    var session: TwitchSession?
    var currentUser: TwitchUser?
    var isAuthorizing = false
    var isSigningOut = false
    var showsAuthenticationError = false
    let chatStore: ChatStore
    let chatAssetStore: ChatAssetStore

    @ObservationIgnored private let authService: any Authenticating
    @ObservationIgnored private let twitchBootstrap: any TwitchBootstrapping
    @ObservationIgnored private var authenticationGrant: AuthenticationGrant?

    init(
        authService: (any Authenticating)? = nil,
        twitchBootstrap: (any TwitchBootstrapping)? = nil,
        chatStore: ChatStore? = nil,
        chatAssetStore: ChatAssetStore? = nil
    ) {
        self.authService = authService ?? AuthService.live()
        self.twitchBootstrap = twitchBootstrap ?? TwitchBootstrapService()
        self.chatStore = chatStore ?? ChatStore()
        self.chatAssetStore = chatAssetStore ?? ChatAssetStore()
    }

    func start() async {
        guard state == .launching else {
            return
        }
        do {
            if let grant = try await authService.restoreAuthentication() {
                apply(grant)
                await loadCurrentUser(for: grant)
            } else {
                state = .signedOut
            }
        } catch {
            clearSession()
            state = .signedOut
            showsAuthenticationError = true
        }
    }

    func signIn() async {
        guard !isAuthorizing else {
            return
        }
        isAuthorizing = true
        showsAuthenticationError = false
        defer { isAuthorizing = false }

        do {
            let grant = try await authService.signIn()
            apply(grant)
            await loadCurrentUser(for: grant)
        } catch {
            showsAuthenticationError = true
        }
    }

    func signOut() async {
        guard !isSigningOut else {
            return
        }
        isSigningOut = true
        defer { isSigningOut = false }

        await chatStore.disconnect()
        chatAssetStore.reset()
        do {
            try await authService.signOut()
            clearSession()
            state = .signedOut
        } catch {
            showsAuthenticationError = true
        }
    }

    func connectChat() async {
        guard let grant = authenticationGrant else {
            chatStore.failChannelResolution()
            return
        }
        let login = chatStore.channelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty else {
            chatStore.failChannelResolution()
            return
        }

        do {
            let channel = try await twitchBootstrap.resolveChannel(login: login, for: grant)
            chatAssetStore.reset()
            await chatStore.connect(
                channel: channel,
                lease: grant.accessLease,
                currentUser: currentUser
            )
            guard chatStore.connectionState == .connected else {
                return
            }

            async let badges: Void = chatAssetStore.loadBadges(
                clientID: grant.accessLease.session.clientID,
                accessToken: grant.accessLease.accessToken,
                broadcasterID: channel.id
            )
            async let betterTTV: Void = chatAssetStore.loadBetterTTV(twitchUserID: channel.id)
            _ = await (badges, betterTTV)

            guard chatStore.channel?.id == channel.id else {
                return
            }
            chatStore.setThirdPartyEmoteCatalog(chatAssetStore.thirdPartyEmoteCatalog)
        } catch {
            chatStore.failChannelResolution()
        }
    }

    func applicationDidEnterBackground() async {
        guard state == .signedIn else {
            return
        }
        await chatStore.suspend()
    }

    func applicationDidBecomeActive() async {
        guard state == .signedIn else {
            return
        }
        await chatStore.resumeIfNeeded()
    }

    private func apply(_ grant: AuthenticationGrant) {
        authenticationGrant = grant
        session = grant.accessLease.session
        chatStore.prepareDefaultChannel(login: grant.accessLease.session.login)
        state = .signedIn
    }

    private func loadCurrentUser(for grant: AuthenticationGrant) async {
        currentUser = try? await twitchBootstrap.loadCurrentUser(for: grant)
    }

    private func clearSession() {
        authenticationGrant = nil
        session = nil
        currentUser = nil
        chatAssetStore.reset()
    }
}
