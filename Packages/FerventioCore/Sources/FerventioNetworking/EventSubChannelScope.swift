import FerventioDomain

enum EventSubChannelScope {
    static func accepts(
        _ envelope: EventSubEnvelope,
        activeChannelID: String?
    ) -> Bool {
        guard envelope.messageType == "notification",
              let activeChannelID,
              !activeChannelID.isEmpty else {
            return true
        }

        if let message = envelope.chatMessage {
            return message.channelID == activeChannelID
        }
        if let poll = envelope.poll {
            return poll.channelID == activeChannelID
        }
        if let prediction = envelope.prediction {
            return prediction.channelID == activeChannelID
        }
        return true
    }
}
