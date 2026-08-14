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
    let interactiveMutationStore: InteractiveChatMutationStore
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
        interactiveMutationStore: InteractiveChatMutationStore? = nil,
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
        self.interactiveMutationStore = interactiveMutationStore ?? InteractiveChatMutationStore()
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
        canExecuteNuke(channel: chatStore.channel)
    }

    var canManagePolls: Bool {
        canManageInteractive(
            scope: "channel:manage:polls",
            channel: chatStore.channel
        )
    }

    var canManagePredictions: Bool {
        canManageInteractive(
            scope: "channel:manage:predictions",
            channel: chatStore.channel
        )
    }

    func canExecuteNuke(in runtime: ChatWorkspaceRuntime) -> Bool {
        canExecuteNuke(channel: runtime.chatStore.channel)
    }

    func canManagePolls(in runtime: ChatWorkspaceRuntime) -> Bool {
        canManageInteractive(
            scope: "channel:manage:polls",
            channel: runtime.chatStore.channel
        )
    }

    func canManagePredictions(in runtime: ChatWorkspaceRuntime) -> Bool {
        canManageInteractive(
            scope: "channel:manage:predictions",
            channel: runtime.chatStore.channel
        )
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
        interactiveMutationStore.clear()
        do {
            try await authService.signOut()
            clearSession()
            state = .signedOut
        } catch {
            showsAuthenticationError = true
        }
    }

    func connectChat() async {
        await connectChat(
            store: chatStore,
            assets: chatAssetStore,
            mutationStore: interactiveMutationStore,
            runtime: nil
        )
    }

    func connectChat(in runtime: ChatWorkspaceRuntime) async {
        guard !runtime.isClosed else {
            return
        }
        await connectChat(
            store: runtime.chatStore,
            assets: runtime.chatAssetStore,
            mutationStore: runtime.interactiveMutationStore,
            runtime: runtime
        )
    }

    func createPoll(_ draft: PollDraft) async -> Bool {
        await createPoll(
            draft,
            store: chatStore,
            mutationStore: interactiveMutationStore
        )
    }

    func createPoll(_ draft: PollDraft, in runtime: ChatWorkspaceRuntime) async -> Bool {
        await createPoll(
            draft,
            store: runtime.chatStore,
            mutationStore: runtime.interactiveMutationStore
        )
    }

    func endPoll(_ poll: PollOverlay, status: PollEndStatus) async -> Bool {
        await endPoll(
            poll,
            status: status,
            store: chatStore,
            mutationStore: interactiveMutationStore
        )
    }

    func endPoll(
        _ poll: PollOverlay,
        status: PollEndStatus,
        in runtime: ChatWorkspaceRuntime
    ) async -> Bool {
        await endPoll(
            poll,
            status: status,
            store: runtime.chatStore,
            mutationStore: runtime.interactiveMutationStore
        )
    }

    func createPrediction(_ draft: PredictionDraft) async -> Bool {
        await createPrediction(
            draft,
            store: chatStore,
            mutationStore: interactiveMutationStore
        )
    }

    func createPrediction(
        _ draft: PredictionDraft,
        in runtime: ChatWorkspaceRuntime
    ) async -> Bool {
        await createPrediction(
            draft,
            store: runtime.chatStore,
            mutationStore: runtime.interactiveMutationStore
        )
    }

    func endPrediction(
        _ prediction: PredictionOverlay,
        status: PredictionEndStatus,
        winningOutcomeID: String? = nil
    ) async -> Bool {
        await endPrediction(
            prediction,
            status: status,
            winningOutcomeID: winningOutcomeID,
            store: chatStore,
            mutationStore: interactiveMutationStore
        )
    }

    func endPrediction(
        _ prediction: PredictionOverlay,
        status: PredictionEndStatus,
        winningOutcomeID: String? = nil,
        in runtime: ChatWorkspaceRuntime
    ) async -> Bool {
        await endPrediction(
            prediction,
            status: status,
            winningOutcomeID: winningOutcomeID,
            store: runtime.chatStore,
            mutationStore: runtime.interactiveMutationStore
        )
    }

    func loadUserProfile(for author: ChatAuthor) async -> TwitchUser? {
        guard let grant = authenticationGrant else {
            return nil
        }
        return try? await userProfileLoader.loadUser(author: author, for: grant)
    }

    func executeNuke(plan: NukeExecutionPlan) async throws -> NukeExecutionResult {
        try await executeNuke(plan: plan, channel: chatStore.channel)
    }

    func executeNuke(
        plan: NukeExecutionPlan,
        in runtime: ChatWorkspaceRuntime
    ) async throws -> NukeExecutionResult {
        try await executeNuke(plan: plan, channel: runtime.chatStore.channel)
    }

    func canTimeoutUser(_ author: ChatAuthor) -> Bool {
        canTimeoutUser(author, channel: chatStore.channel)
    }

    func canTimeoutUser(_ author: ChatAuthor, in runtime: ChatWorkspaceRuntime) -> Bool {
        canTimeoutUser(author, channel: runtime.chatStore.channel)
    }

    func timeoutUserFromCard(_ author: ChatAuthor) async throws -> NukeExecutionResult {
        try await timeoutUserFromCard(author, channel: chatStore.channel)
    }

    func timeoutUserFromCard(
        _ author: ChatAuthor,
        in runtime: ChatWorkspaceRuntime
    ) async throws -> NukeExecutionResult {
        try await timeoutUserFromCard(author, channel: runtime.chatStore.channel)
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

    private func connectChat(
        store: ChatStore,
        assets: ChatAssetStore,
        mutationStore: InteractiveChatMutationStore,
        runtime: ChatWorkspaceRuntime?
    ) async {
        guard connectionRequestIsValid(runtime) else {
            return
        }
        guard let grant = authenticationGrant else {
            store.failChannelResolution()
            return
        }
        let login = store.channelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty else {
            store.failChannelResolution()
            return
        }

        do {
            let channel = try await twitchBootstrap.resolveChannel(login: login, for: grant)
            guard connectionRequestIsValid(runtime) else {
                return
            }

            assets.reset()
            mutationStore.clear()
            await store.connect(
                channel: channel,
                lease: grant.accessLease,
                currentUser: currentUser
            )
            guard connectionRequestIsValid(runtime) else {
                await store.disconnect()
                assets.reset()
                mutationStore.clear()
                return
            }
            guard store.connectionState == .connected else {
                return
            }

            async let badges: Void = assets.loadBadges(
                clientID: grant.accessLease.session.clientID,
                accessToken: grant.accessLease.accessToken,
                broadcasterID: channel.id
            )
            async let thirdPartyEmotes: Void = assets.loadThirdPartyEmotes(
                twitchUserID: channel.id
            )
            async let interactiveSnapshot = interactiveChatHydrator.load(
                channel: channel,
                lease: grant.accessLease
            )
            let (_, _, snapshot) = await (badges, thirdPartyEmotes, interactiveSnapshot)

            guard connectionRequestIsValid(runtime) else {
                await store.disconnect()
                assets.reset()
                mutationStore.clear()
                return
            }
            guard store.channel?.id == channel.id else {
                return
            }
            store.setThirdPartyEmoteCatalog(assets.thirdPartyEmoteCatalog)
            store.applyHydratedInteractiveOverlays(snapshot)
        } catch is CancellationError {
            if connectionRequestIsValid(runtime) {
                store.failChannelResolution()
            }
        } catch {
            if connectionRequestIsValid(runtime) {
                store.failChannelResolution()
            }
        }
    }

    private func createPoll(
        _ draft: PollDraft,
        store: ChatStore,
        mutationStore: InteractiveChatMutationStore
    ) async -> Bool {
        guard let grant = authenticationGrant,
              let channel = store.channel else {
            return false
        }
        let success = await mutationStore.createPoll(
            channel: channel,
            lease: grant.accessLease,
            draft: draft
        )
        if success {
            await refreshInteractiveOverlays(
                channel: channel,
                grant: grant,
                store: store
            )
        }
        return success
    }

    private func endPoll(
        _ poll: PollOverlay,
        status: PollEndStatus,
        store: ChatStore,
        mutationStore: InteractiveChatMutationStore
    ) async -> Bool {
        guard let grant = authenticationGrant,
              let channel = store.channel,
              poll.channelID == channel.id else {
            return false
        }
        let success = await mutationStore.endPoll(
            channel: channel,
            lease: grant.accessLease,
            pollID: poll.id,
            status: status
        )
        if success {
            await refreshInteractiveOverlays(
                channel: channel,
                grant: grant,
                store: store
            )
        }
        return success
    }

    private func createPrediction(
        _ draft: PredictionDraft,
        store: ChatStore,
        mutationStore: InteractiveChatMutationStore
    ) async -> Bool {
        guard let grant = authenticationGrant,
              let channel = store.channel else {
            return false
        }
        let success = await mutationStore.createPrediction(
            channel: channel,
            lease: grant.accessLease,
            draft: draft
        )
        if success {
            await refreshInteractiveOverlays(
                channel: channel,
                grant: grant,
                store: store
            )
        }
        return success
    }

    private func endPrediction(
        _ prediction: PredictionOverlay,
        status: PredictionEndStatus,
        winningOutcomeID: String?,
        store: ChatStore,
        mutationStore: InteractiveChatMutationStore
    ) async -> Bool {
        guard let grant = authenticationGrant,
              let channel = store.channel,
              prediction.channelID == channel.id else {
            return false
        }
        let success = await mutationStore.endPrediction(
            channel: channel,
            lease: grant.accessLease,
            predictionID: prediction.id,
            status: status,
            winningOutcomeID: winningOutcomeID
        )
        if success {
            await refreshInteractiveOverlays(
                channel: channel,
                grant: grant,
                store: store
            )
        }
        return success
    }

    private func executeNuke(
        plan: NukeExecutionPlan,
        channel: ChatChannel?
    ) async throws -> NukeExecutionResult {
        guard let grant = authenticationGrant else {
            throw NukeExecutionServiceError.notAuthenticated
        }
        guard let channel else {
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

    private func canTimeoutUser(
        _ author: ChatAuthor,
        channel: ChatChannel?
    ) -> Bool {
        guard canExecuteNuke(channel: channel),
              let session,
              !author.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              author.id != session.userID else {
            return false
        }
        let badgeSetIDs = Set(author.badges.map(\.setID))
        return badgeSetIDs.isDisjoint(with: Self.protectedModerationBadgeSetIDs)
    }

    private func timeoutUserFromCard(
        _ author: ChatAuthor,
        channel: ChatChannel?
    ) async throws -> NukeExecutionResult {
        guard canTimeoutUser(author, channel: channel) else {
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
        return try await executeNuke(plan: plan, channel: channel)
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

    private func refreshInteractiveOverlays(
        channel: ChatChannel,
        grant: AuthenticationGrant,
        store: ChatStore
    ) async {
        let snapshot = await interactiveChatHydrator.load(
            channel: channel,
            lease: grant.accessLease
        )
        guard store.channel?.id == channel.id else {
            return
        }
        store.applyHydratedInteractiveOverlays(snapshot)
    }

    private func connectionRequestIsValid(_ runtime: ChatWorkspaceRuntime?) -> Bool {
        runtime?.isClosed != true
    }

    private func canExecuteNuke(channel: ChatChannel?) -> Bool {
        guard let grant = authenticationGrant,
              channel != nil else {
            return false
        }
        return grant.accessLease.session.scopes.contains(TwitchNukeExecutionService.requiredScope)
    }

    private func canManageInteractive(
        scope: String,
        channel: ChatChannel?
    ) -> Bool {
        guard let grant = authenticationGrant,
              let channel,
              channel.id == grant.accessLease.session.userID else {
            return false
        }
        return grant.accessLease.session.scopes.contains(scope)
    }

    private func clearSession() {
        authenticationGrant = nil
        session = nil
        currentUser = nil
        chatHistoryPager.reset(channelID: nil)
        chatAssetStore.reset()
        interactiveMutationStore.clear()
    }

    private static let protectedModerationBadgeSetIDs: Set<String> = [
        "broadcaster",
        "moderator",
        "vip",
    ]
}
