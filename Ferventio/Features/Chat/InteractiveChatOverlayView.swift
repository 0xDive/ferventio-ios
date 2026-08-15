import FerventioDomain
import SwiftUI

struct InteractiveChatOverlayView: View {
    let poll: PollOverlay?
    let prediction: PredictionOverlay?

    var body: some View {
        if poll != nil || prediction != nil {
            VStack(spacing: 8) {
                if let poll {
                    pollCard(poll)
                }
                if let prediction {
                    predictionCard(prediction)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func pollCard(_ poll: PollOverlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(
                systemImage: "chart.bar.fill",
                kind: localized("interactive.poll"),
                title: poll.title,
                status: pollStatus(poll.status)
            )

            ForEach(poll.choices) { choice in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(choice.title)
                            .font(.subheadline)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(choice.votes.formatted())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: poll.voteShare(choiceID: choice.id))
                        .accessibilityLabel(Text(choice.title))
                        .accessibilityValue(Text(percent(poll.voteShare(choiceID: choice.id))))
                }
            }

            HStack {
                Text(localized("interactive.total_votes"))
                Spacer(minLength: 8)
                Text(poll.totalVotes.formatted())
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func predictionCard(_ prediction: PredictionOverlay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header(
                systemImage: "sparkles",
                kind: localized("interactive.prediction"),
                title: prediction.title,
                status: predictionStatus(prediction.status)
            )

            ForEach(prediction.outcomes) { outcome in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        if prediction.winningOutcomeID == outcome.id {
                            Image(systemName: "checkmark.circle.fill")
                                .accessibilityLabel(Text(localized("interactive.winner")))
                        }
                        Text(outcome.title)
                            .font(.subheadline)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text(outcome.channelPoints.formatted())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: prediction.pointsShare(outcomeID: outcome.id))
                        .accessibilityLabel(Text(outcome.title))
                        .accessibilityValue(
                            Text(percent(prediction.pointsShare(outcomeID: outcome.id)))
                        )
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    predictionUsersLabel(prediction)
                    Spacer(minLength: 8)
                    predictionPointsLabel(prediction)
                }

                VStack(alignment: .leading, spacing: 4) {
                    predictionUsersLabel(prediction)
                    predictionPointsLabel(prediction)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func header(
        systemImage: String,
        kind: String,
        title: String,
        status: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    kindLabel(systemImage: systemImage, kind: kind)
                    Spacer(minLength: 8)
                    statusLabel(status)
                }

                VStack(alignment: .leading, spacing: 2) {
                    kindLabel(systemImage: systemImage, kind: kind)
                    statusLabel(status)
                }
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func kindLabel(systemImage: String, kind: String) -> some View {
        Label(kind, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func statusLabel(_ status: String) -> some View {
        Text(status)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func predictionUsersLabel(_ prediction: PredictionOverlay) -> some View {
        Label(
            prediction.totalUsers.formatted(),
            systemImage: "person.2"
        )
    }

    private func predictionPointsLabel(_ prediction: PredictionOverlay) -> some View {
        Label(
            prediction.totalChannelPoints.formatted(),
            systemImage: "diamond.fill"
        )
    }

    private func pollStatus(_ status: PollStatus) -> String {
        switch status {
        case .active: localized("interactive.status.active")
        case .completed: localized("interactive.status.completed")
        case .terminated: localized("interactive.status.terminated")
        case .archived: localized("interactive.status.archived")
        case .moderated: localized("interactive.status.moderated")
        case .invalid: localized("interactive.status.invalid")
        case .unknown: localized("interactive.status.unknown")
        }
    }

    private func predictionStatus(_ status: PredictionStatus) -> String {
        switch status {
        case .active: localized("interactive.status.active")
        case .locked: localized("interactive.status.locked")
        case .resolved: localized("interactive.status.resolved")
        case .canceled: localized("interactive.status.canceled")
        case .unknown: localized("interactive.status.unknown")
        }
    }

    private func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func localized(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "InteractiveChat")
    }
}
