import FerventioDomain
import SwiftUI

struct InteractiveChatManagementView: View {
    let poll: PollOverlay?
    let prediction: PredictionOverlay?
    let canManagePolls: Bool
    let canManagePredictions: Bool
    @Bindable var mutationStore: InteractiveChatMutationStore
    let createPoll: (PollDraft) async -> Bool
    let createPrediction: (PredictionDraft) async -> Bool
    let endPoll: (PollOverlay, PollEndStatus) async -> Bool
    let endPrediction: (PredictionOverlay, PredictionEndStatus, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var winningOutcomeID: String?
    @State private var pollTitle = ""
    @State private var pollChoices = ["", ""]
    @State private var pollDurationSeconds = 60
    @State private var predictionTitle = ""
    @State private var predictionOutcomes = ["", ""]
    @State private var predictionWindowSeconds = 60
    @State private var showsPollValidationError = false
    @State private var showsPredictionValidationError = false

    var body: some View {
        NavigationStack {
            Form {
                pollSection
                predictionSection
                mutationStatusSection
            }
            .navigationTitle(localized("interactive.manage.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("interactive.manage.done")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var pollSection: some View {
        if let poll {
            Section(localized("interactive.poll")) {
                Text(poll.title)
                if canManagePolls {
                    Button(localized("interactive.manage.terminate"), role: .destructive) {
                        Task { _ = await endPoll(poll, .terminated) }
                    }
                    .disabled(isMutating)
                    Button(localized("interactive.manage.archive")) {
                        Task { _ = await endPoll(poll, .archived) }
                    }
                    .disabled(isMutating)
                }
            }
        }

        if canManagePolls && poll?.isActive != true {
            Section(localized("interactive.manage.poll.create")) {
                TextField(localized("interactive.manage.title_field"), text: $pollTitle)
                InteractiveOptionListEditor(
                    label: localized("interactive.manage.choice"),
                    maximumCount: 5,
                    values: $pollChoices
                )
                Picker(localized("interactive.manage.duration"), selection: $pollDurationSeconds) {
                    ForEach(Self.pollDurations, id: \.self) { seconds in
                        Text(durationLabel(seconds)).tag(seconds)
                    }
                }
                if showsPollValidationError {
                    Text(localized("interactive.manage.invalid"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button(localized("interactive.manage.create")) {
                    Task { await submitPoll() }
                }
                .disabled(isMutating)
            }
        }
    }

    @ViewBuilder
    private var predictionSection: some View {
        if let prediction {
            Section(localized("interactive.prediction")) {
                Text(prediction.title)
                if canManagePredictions {
                    if prediction.isActive {
                        Button(localized("interactive.manage.lock")) {
                            Task { _ = await endPrediction(prediction, .locked, nil) }
                        }
                        .disabled(isMutating)
                    }
                    if prediction.isActive || prediction.isLocked {
                        Button(localized("interactive.manage.cancel"), role: .destructive) {
                            Task { _ = await endPrediction(prediction, .canceled, nil) }
                        }
                        .disabled(isMutating)
                    }
                    if prediction.isLocked {
                        Picker(localized("interactive.manage.winner"), selection: $winningOutcomeID) {
                            Text("—").tag(String?.none)
                            ForEach(prediction.outcomes) { outcome in
                                Text(outcome.title).tag(Optional(outcome.id))
                            }
                        }
                        Button(localized("interactive.manage.resolve")) {
                            guard let winningOutcomeID else { return }
                            Task {
                                _ = await endPrediction(
                                    prediction,
                                    .resolved,
                                    winningOutcomeID
                                )
                            }
                        }
                        .disabled(isMutating || winningOutcomeID == nil)
                    }
                }
            }
        }

        if canManagePredictions && prediction?.isActive != true && prediction?.isLocked != true {
            Section(localized("interactive.manage.prediction.create")) {
                TextField(localized("interactive.manage.title_field"), text: $predictionTitle)
                InteractiveOptionListEditor(
                    label: localized("interactive.manage.outcome"),
                    maximumCount: 10,
                    values: $predictionOutcomes
                )
                Picker(localized("interactive.manage.window"), selection: $predictionWindowSeconds) {
                    ForEach(Self.predictionWindows, id: \.self) { seconds in
                        Text(durationLabel(seconds)).tag(seconds)
                    }
                }
                if showsPredictionValidationError {
                    Text(localized("interactive.manage.invalid"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button(localized("interactive.manage.create")) {
                    Task { await submitPrediction() }
                }
                .disabled(isMutating)
            }
        }
    }

    @ViewBuilder
    private var mutationStatusSection: some View {
        if let status = mutationStore.status {
            Section {
                if status.inFlight {
                    ProgressView(localized("interactive.manage.applying"))
                } else if status.failed {
                    Text(localized("interactive.manage.failed"))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var isMutating: Bool {
        mutationStore.status?.inFlight == true
    }

    private func submitPoll() async {
        let draft = PollDraft(
            title: pollTitle,
            choices: normalized(pollChoices),
            durationSeconds: pollDurationSeconds
        )
        guard InteractiveOverlayDraftValidator.validate(draft).isEmpty else {
            showsPollValidationError = true
            return
        }
        showsPollValidationError = false
        if await createPoll(draft) {
            pollTitle = ""
            pollChoices = ["", ""]
        }
    }

    private func submitPrediction() async {
        let draft = PredictionDraft(
            title: predictionTitle,
            outcomes: normalized(predictionOutcomes),
            predictionWindowSeconds: predictionWindowSeconds
        )
        guard InteractiveOverlayDraftValidator.validate(draft).isEmpty else {
            showsPredictionValidationError = true
            return
        }
        showsPredictionValidationError = false
        if await createPrediction(draft) {
            predictionTitle = ""
            predictionOutcomes = ["", ""]
        }
    }

    private func normalized(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func durationLabel(_ seconds: Int) -> String {
        if seconds % 60 == 0 {
            return "\(seconds / 60) \(localized("interactive.manage.minutes_short"))"
        }
        return "\(seconds) \(localized("interactive.manage.seconds_short"))"
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "InteractiveChat")
    }

    private static let pollDurations = [15, 30, 60, 120, 300, 600, 900, 1_800]
    private static let predictionWindows = [30, 60, 120, 300, 600, 900, 1_800]
}
