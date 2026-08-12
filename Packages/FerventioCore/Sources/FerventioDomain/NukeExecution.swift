import Foundation

public struct NukeExecutionPolicy: Equatable, Sendable {
    public var timeoutSeconds: Int
    public var reason: String
    public var maxTargetUsers: Int
    public var delayBetweenActionsMilliseconds: Int64

    public init(
        timeoutSeconds: Int = 600,
        reason: String = "Mass moderation",
        maxTargetUsers: Int = 100,
        delayBetweenActionsMilliseconds: Int64 = 175
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.reason = reason
        self.maxTargetUsers = maxTargetUsers
        self.delayBetweenActionsMilliseconds = delayBetweenActionsMilliseconds
    }
}

public struct NukeTargetFailure: Equatable, Sendable, Identifiable {
    public let user: NukeTargetUser
    public let message: String

    public var id: String { user.id }

    public init(user: NukeTargetUser, message: String) {
        self.user = user
        self.message = message
    }
}

public struct NukeExecutionResult: Equatable, Sendable {
    public let attemptedUsers: Int
    public let succeededUsers: Int
    public let failures: [NukeTargetFailure]

    public var failedUsers: Int { failures.count }
    public var completed: Bool { attemptedUsers > 0 && failures.isEmpty }

    public init(
        attemptedUsers: Int,
        succeededUsers: Int,
        failures: [NukeTargetFailure]
    ) {
        self.attemptedUsers = attemptedUsers
        self.succeededUsers = succeededUsers
        self.failures = failures
    }
}

public enum NukeExecutionCoordinatorError: Swift.Error, Equatable, Sendable {
    case invalidTimeoutDuration
    case invalidTargetLimit
    case invalidDelay
    case emptyTargetSet
    case targetLimitExceeded(limit: Int)
}

public struct NukeExecutionCoordinator: Sendable {
    public typealias ModerationAction = @Sendable (
        _ user: NukeTargetUser,
        _ durationSeconds: Int,
        _ reason: String
    ) async throws -> Void
    public typealias DelayAction = @Sendable (_ milliseconds: Int64) async throws -> Void

    private let moderationAction: ModerationAction
    private let delayAction: DelayAction

    public init(
        moderationAction: @escaping ModerationAction,
        delayAction: @escaping DelayAction = { milliseconds in
            guard milliseconds > 0 else { return }
            try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
        }
    ) {
        self.moderationAction = moderationAction
        self.delayAction = delayAction
    }

    public func execute(
        plan: NukeExecutionPlan,
        policy: NukeExecutionPolicy = NukeExecutionPolicy()
    ) async throws -> NukeExecutionResult {
        guard policy.timeoutSeconds > 0 else {
            throw NukeExecutionCoordinatorError.invalidTimeoutDuration
        }
        guard policy.maxTargetUsers > 0 else {
            throw NukeExecutionCoordinatorError.invalidTargetLimit
        }
        guard policy.delayBetweenActionsMilliseconds >= 0 else {
            throw NukeExecutionCoordinatorError.invalidDelay
        }
        guard !plan.targetUsers.isEmpty else {
            throw NukeExecutionCoordinatorError.emptyTargetSet
        }
        guard plan.targetUsers.count <= policy.maxTargetUsers else {
            throw NukeExecutionCoordinatorError.targetLimitExceeded(limit: policy.maxTargetUsers)
        }

        var failures: [NukeTargetFailure] = []
        var succeeded = 0

        for (index, user) in plan.targetUsers.enumerated() {
            do {
                try await moderationAction(user, policy.timeoutSeconds, policy.reason)
                succeeded += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(
                    NukeTargetFailure(
                        user: user,
                        message: String(describing: error)
                    )
                )
            }

            if index < plan.targetUsers.count - 1,
               policy.delayBetweenActionsMilliseconds > 0 {
                try await delayAction(policy.delayBetweenActionsMilliseconds)
            }
        }

        return NukeExecutionResult(
            attemptedUsers: plan.targetUsers.count,
            succeededUsers: succeeded,
            failures: failures
        )
    }
}
