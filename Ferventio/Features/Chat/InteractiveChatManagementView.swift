import FerventioDomain
import SwiftUI

struct InteractiveChatManagementView: View {
    let poll: PollOverlay?
    let prediction: PredictionOverlay?
    let canManagePolls: Bool
    let canManagePredictions: Bool
    @Bindable var mutationStore: InteractiveChatMutationStore
    let endPoll: (PollOverlay, PollEndStatus) async -> Bool
    let endPrediction: (PredictionOverlay, PredictionEndStatus, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var winningOutcomeID: String?

    var body: some View {
        NavigationStack {
            Form {
                if let poll {
                    Section(localized("interactive.poll")) {
                        Text(poll.title)
                        if canManagePolls {
                            Button(localized("interactive.manage.terminate"), role: .destructive) {
                                Task { _ = await endPoll(poll, .terminated) }
                            }
                            Button(localized("interactive.manage.archive")) {
                                Task { _ = await endPoll(poll, .archived) }
                            }
                        }
                    }
                }

                if let prediction {
                    Section(localized("interactive.prediction")) {
                        Text(prediction.title)
                        if canManagePredictions {
                            if prediction.isActive {
                                Button(localized("interactive.manage.lock")) {
                                    Task { _ = await endPrediction(prediction, .locked, nil) }
                                }
                            }
                            if prediction.isActive || prediction.isLocked {
                                Button(localized("interactive.manage.cancel"), role: .destructive) {
                                    Task { _ = await endPrediction(prediction, .canceled, nil) }
                                }
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
                                .disabled(winningOutcomeID == nil)
                            }
                        }
                    }
                }

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
            .navigationTitle(localized("interactive.manage.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("interactive.manage.done")) { dismiss() }
                }
            }
        }
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "InteractiveChat")
    }
}