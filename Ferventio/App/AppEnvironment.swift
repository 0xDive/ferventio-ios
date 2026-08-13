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
    let chatHistoryPager: ChatHistoryPager
    var chatPresentationPreferences: ChatPresentationPreferences

    @ObservationIgnored private let authService: any Authenticating
    @ObservationIgnored private let twitchBootstrap: any TwitchBootstrapping
    @ObservationIgnored private let userProfileLoader: any UserProfileLoading
    @ObservationIgnored private let nukeExecutor: any NukeExecuting
    @ObservationIgnored private let interactiveChatHydrator: any InteractiveChatHydrating
    @ObservationIgnored private let chatHistoryPreferencesStore: ChatHistoryPreferencesStore
    @ObservationIgnored private let chatPresentationPreferencesStore: ChatPresentationPreferencesStore
    @ObservationIgnored private var authenticationGrant: AuthenticationGrant?

    init(
        authService: (any Authenticating)? = nil,
        twitchBootstrap: (any TwitchBootstrapping)? = nil,
        userProfileLoader: (any UserProfileLoading)? = nil,
        nukeExecutor: (any NukeExecuting)? = nil,
        interactiveChatHydrator: (any InteractiveChatHydrating)? = nil,
        chatStore: ChatStore? = nil,
        chatAssetStore: ChatAssetStore? = nil,
        chatHistoryPager: ChatHistoryPager? = nil,
        chatHistoryPreferencesStore: ChatHistoryPreferencesStore? = nil,
        chatPresentationPreferencesStore: ChatPresentationPreferencesStore? = nil
    ) {
        self.authService = authService ?? AuthService.live()
        self.twitchBootstrap = twitchBootstrap ?? TwitchBootstrapService()
        self.userProfileLoader = userProfileLoader ?? TwitchUserProfileLoader()
        self.nukeExecutor = nukeExecutor ?? TwitchNukeExecutionService()
        self.interactiveChatHydrator = interactiveChatHydrator ?? TwitchInteractiveChatHydrator()
        let preferencesStore = chatHistoryPreferencesStore ?? ChatHistoryPreferencesStore()
        let preferences = preferencesStore.load()
        self.chatHistoryPreferencesStore = preferencesStore
        let presentationPreferencesStore = chatPresentationPreferencesStore
            ?? ChatPresentationPreferencesStore()
        self.chatPresentationPreferencesStore = presentationPreferencesStore
        self.chatPresentationPreferences = presentationPreferencesStore.load()

        if let chatStore {
            self.chatStore = chatStore
            self.chatHistoryPager = chatHistoryPager ?? ChatHistoryPager(
                history: NoopChatHistory(),
                preferences: preferences
            )
        } else {
            let history = ChatHistoryFactory.live()
            self.chatStore = ChatStore(
                history: history,
                recentMessagesLoader: RecentMessagesLoaderFactory.live(),
                historyPreferences: preferences
            )
            self.chatHistoryPager = chatHistoryPager ?? ChatHistoryPager(
                history: history,
                preferences: preferences
            )
        }
        self.chatAssetStore = chatAssetStore ?? ChatAssetStore()
    }

    var canExecuteNuke: Bool {
        guard let grant = authenticationGrant,
              chatStore.channel != nil else {
            return false
        }
        return grant.accessLease.session.scopes.contains(TwitchNukeExecutionService.requiredScope)
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
        chatHistoryPager.reset(channelID: nil)
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
            async let thirdPartyEmotes: Void = chatAssetStore.loadThirdPartyEmotes(
                twitchUserID: channel.id
            )
            async let interactiveSnapshot = interactiveChatHydrator.load(
                channel: channel,
                lease: grant.accessLease
            )
            let (_, _, snapshot) = await (badges, thirdPartyEmotes, interactiveSnapshot)

            guard chatStore.channel?.id == channel.id else {
                return
            }
            chatStore.setThirdPartyEmoteCatalog(chatAssetStore.thirdPartyEmoteCatalog)
            chatStore.applyHydratedInteractiveOverlays(snapshot)
        } catch {
            chatStore.failChannelResolution()
        }
    }

    func loadUserProfile(for author: ChatAuthor) async -> TwitchUser? {
        guard let grant = authenticationGrant else {
            return nil
        }
        return try? await userProfileLoader.loadUser(author: author, for: grant)
    }

    func executeNuke(plan: NukeExecutionPlan) async throws -> NukeExecutionResult {
        guard let grant = authenticationGrant else {
            throw NukeExecutionServiceError.notAuthenticated
        }
        guard let channel = chatStore.channel else {
            throw NukeExecutionServiceError.missingChannel
        }
        guard grant.accessLease.session.scopes.contains(TwitchNukeExecutionService.requiredScope) else {
            throw NukeExecutionServiceError.missingScope
        }
        return try await nukeExecutor.execute(
            plan: plan,
            broadcasterID: channel.id,
            grant: grant
        )
    }

    func canTimeoutUser(_ author: ChatAuthor) -> Bool {
        guard canExecuteNuke,
              let session,
              !author.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              author.id != session.userID else {
            return false
        }
        let badgeSetIDs = Set(author.badges.map(\.setID))
        return badgeSetIDs.isDisjoint(with: Self.protectedModerationBadgeSetIDs)
    }

    func timeoutUserFromCard(_ author: ChatAuthor) async throws -> NukeExecutionResult {
        guard canTimeoutUser(author) else {
            throw NukeExecutionServiceError.missingTargetUserID
        }
        let user = NukeTargetUser(
            userID: author.id,
            userLogin: author.login,
            userDisplayName: author.displayName
        )
        let plan = NukeExecutionPlan(
            query: "manual:user-card-timeout",
            matchMode: .plainText,
            caseSensitive: false,
            previewedAtMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            targetUsers: [user],
            targetMessageIDs: []
        )
        return try await executeNuke(plan: plan)
    }

    func chatHistoryPreferences() -> ChatHistoryPreferences {
        chatHistoryPreferencesStore.load()
    }

    @discardableResult
    func updateChatHistoryPreferences(
        _ preferences: ChatHistoryPreferences
    ) async -> ChatHistoryPreferences {
        let saved = chatHistoryPreferencesStore.save(preferences)
        await chatStore.updateHistoryPreferences(saved)
        chatHistoryPager.updatePreferences(saved)
        return saved
    }

    @discardableResult
    func updateChatPresentationPreferences(
        _ preferences: ChatPresentationPreferences
    ) -> ChatPresentationPreferences {
        let saved = chatPresentationPreferencesStore.save(preferences)
        chatPresentationPreferences = saved
        return saved
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
        chatHistoryPager.reset(channelID: nil)
        chatAssetStore.reset()
    }

    private static let protectedModerationBadgeSetIDs: Set<String> = [
        "broadcaster",
        "moderator",
        "vip",
    ]
}
