public struct TwitchUser: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let login: String
    public let displayName: String
    public let profileImageURL: String?
    public let createdAt: String?
    public let broadcasterType: String?
    public let description: String?

    public init(
        id: String,
        login: String,
        displayName: String,
        profileImageURL: String?,
        createdAt: String?,
        broadcasterType: String?,
        description: String?
    ) {
        self.id = id
        self.login = login
        self.displayName = displayName
        self.profileImageURL = profileImageURL
        self.createdAt = createdAt
        self.broadcasterType = broadcasterType
        self.description = description
    }
}
