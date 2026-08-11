public struct ChatChannel: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let login: String
    public let displayName: String
    public let profileImageURL: String?

    public init(
        id: String,
        login: String,
        displayName: String,
        profileImageURL: String? = nil
    ) {
        self.id = id
        self.login = login
        self.displayName = displayName
        self.profileImageURL = profileImageURL
    }
}
