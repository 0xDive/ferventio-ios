import FerventioDomain

extension AppEnvironment {
    func endPollAndReconcile(
        _ poll: PollOverlay,
        status: PollEndStatus
    ) async -> Bool {
        let success = await endPoll(poll, status: status)
        if success {
            chatStore.applyConfirmedPollMutation(poll, status: status)
        }
        return success
    }

    func endPollAndReconcile(
        _ poll: PollOverlay,
        status: PollEndStatus,
        in runtime: ChatWorkspaceRuntime
    ) async -> Bool {
        let success = await endPoll(poll, status: status, in: runtime)
        if success {
            runtime.chatStore.applyConfirmedPollMutation(poll, status: status)
        }
        return success
    }

    func endPredictionAndReconcile(
        _ prediction: PredictionOverlay,
        status: PredictionEndStatus,
        winningOutcomeID: String? = nil
    ) async -> Bool {
        let success = await endPrediction(
            prediction,
            status: status,
            winningOutcomeID: winningOutcomeID
        )
        if success {
            chatStore.applyConfirmedPredictionMutation(
                prediction,
                status: status,
                winningOutcomeID: winningOutcomeID
            )
        }
        return success
    }

    func endPredictionAndReconcile(
        _ prediction: PredictionOverlay,
        status: PredictionEndStatus,
        winningOutcomeID: String? = nil,
        in runtime: ChatWorkspaceRuntime
    ) async -> Bool {
        let success = await endPrediction(
            prediction,
            status: status,
            winningOutcomeID: winningOutcomeID,
            in: runtime
        )
        if success {
            runtime.chatStore.applyConfirmedPredictionMutation(
                prediction,
                status: status,
                winningOutcomeID: winningOutcomeID
            )
        }
        return success
    }
}
