import Foundation

public actor EventSubWebSocketConnection {
    public enum Error: Swift.Error, Equatable {
        case alreadyConnected
        case notConnected
        case invalidURL
        case welcomeTimedOut
        case keepaliveTimedOut
        case invalidWelcome(String)
        case unsupportedMessage
        case invalidTextFrame
    }

    public static let defaultURL = URL(
        string: "wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30"
    )!

    public static let welcomeTimeoutSeconds = 15
    public static let defaultKeepaliveSeconds = 30
    public static let minimumKeepaliveSeconds = 10
    public static let maximumKeepaliveSeconds = 600
    public static let keepaliveGraceSeconds = 10

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var keepaliveSeconds = defaultKeepaliveSeconds

    public init(session: URLSession = .shared) {
        self.session = session
    }

    deinit {
        task?.cancel(with: .goingAway, reason: nil)
    }

    @discardableResult
    public func connect(to url: URL = defaultURL) async throws -> EventSubEnvelope {
        guard task == nil else {
            throw Error.alreadyConnected
        }
        let socket = try makeSocket(for: url)
        task = socket
        socket.resume()

        do {
            let welcome = try await Self.receiveEnvelope(
                from: socket,
                timeoutSeconds: Self.welcomeTimeoutSeconds,
                timeoutError: .welcomeTimedOut
            )
            try applyWelcome(welcome)
            return welcome
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            task = nil
            throw error
        }
    }

    public func receive() async throws -> EventSubEnvelope {
        guard let task else {
            throw Error.notConnected
        }
        return try await Self.receiveEnvelope(
            from: task,
            timeoutSeconds: keepaliveSeconds + Self.keepaliveGraceSeconds,
            timeoutError: .keepaliveTimedOut
        )
    }

    @discardableResult
    public func migrate(to reconnectURL: URL) async throws -> EventSubEnvelope {
        guard let previousTask = task else {
            throw Error.notConnected
        }
        let replacement = try makeSocket(for: reconnectURL)
        replacement.resume()

        do {
            let welcome = try await Self.receiveEnvelope(
                from: replacement,
                timeoutSeconds: Self.welcomeTimeoutSeconds,
                timeoutError: .welcomeTimedOut
            )
            try applyWelcome(welcome)
            task = replacement
            previousTask.cancel(with: .goingAway, reason: nil)
            return welcome
        } catch {
            replacement.cancel(with: .goingAway, reason: nil)
            throw error
        }
    }

    public func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        keepaliveSeconds = Self.defaultKeepaliveSeconds
    }

    static func isAllowedEventSubURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "wss",
              url.host?.lowercased() == "eventsub.wss.twitch.tv",
              url.user == nil,
              url.password == nil,
              url.fragment == nil else {
            return false
        }
        return true
    }

    private func makeSocket(for url: URL) throws -> URLSessionWebSocketTask {
        guard Self.isAllowedEventSubURL(url) else {
            throw Error.invalidURL
        }
        return session.webSocketTask(with: url)
    }

    private func applyWelcome(_ envelope: EventSubEnvelope) throws {
        guard envelope.messageType == "session_welcome" else {
            throw Error.invalidWelcome(envelope.messageType)
        }
        guard envelope.sessionID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw Error.invalidWelcome("missing session id")
        }
        keepaliveSeconds = min(
            max(envelope.keepaliveTimeoutSeconds ?? Self.defaultKeepaliveSeconds, Self.minimumKeepaliveSeconds),
            Self.maximumKeepaliveSeconds
        )
    }

    private nonisolated static func receiveEnvelope(
        from task: URLSessionWebSocketTask,
        timeoutSeconds: Int,
        timeoutError: Error
    ) async throws -> EventSubEnvelope {
        try await withThrowingTaskGroup(of: EventSubEnvelope.self) { group in
            group.addTask {
                try await receiveEnvelope(from: task)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                throw timeoutError
            }

            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw timeoutError
            }
            return first
        }
    }

    private nonisolated static func receiveEnvelope(
        from task: URLSessionWebSocketTask
    ) async throws -> EventSubEnvelope {
        while !Task.isCancelled {
            let message = try await task.receive()
            switch message {
            case let .string(raw):
                return try EventSubEnvelopeParser.parse(raw)

            case let .data(data):
                guard data.count <= EventSubEnvelopeParser.maximumEnvelopeBytes,
                      let raw = String(data: data, encoding: .utf8) else {
                    throw Error.invalidTextFrame
                }
                return try EventSubEnvelopeParser.parse(raw)

            @unknown default:
                throw Error.unsupportedMessage
            }
        }
        throw CancellationError()
    }
}
