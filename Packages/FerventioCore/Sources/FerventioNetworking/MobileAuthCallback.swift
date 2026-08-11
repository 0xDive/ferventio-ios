import Foundation

public enum MobileAuthCallback {
    public struct Handoff: Equatable, Sendable {
        public let code: String
        public let state: String

        public init(code: String, state: String) {
            self.code = code
            self.state = state
        }
    }

    public enum Error: Swift.Error, Equatable {
        case invalidURL
        case stateMismatch
        case authorizationDenied(String)
        case missingCode
    }

    public static func parse(
        _ url: URL,
        expectedScheme: String,
        expectedState: String
    ) throws -> Handoff {
        guard url.scheme == expectedScheme,
              url.host == "oauth",
              url.path == "/callback",
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Error.invalidURL
        }

        guard let state = try singleValue(named: "state", in: components),
              state == expectedState else {
            throw Error.stateMismatch
        }
        if let errorCode = try singleValue(named: "error", in: components, required: false),
           !errorCode.isEmpty {
            throw Error.authorizationDenied(errorCode)
        }
        guard let code = try singleValue(named: "code", in: components, required: false),
              !code.isEmpty else {
            throw Error.missingCode
        }
        return Handoff(code: code, state: state)
    }

    private static func singleValue(
        named name: String,
        in components: URLComponents,
        required: Bool = true
    ) throws -> String? {
        let values = components.queryItems?
            .filter { $0.name == name }
            .map { $0.value ?? "" } ?? []
        guard values.count <= 1 else {
            throw Error.invalidURL
        }
        guard let value = values.first else {
            if required {
                throw Error.invalidURL
            }
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if required && trimmed.isEmpty {
            throw Error.invalidURL
        }
        return trimmed
    }
}
