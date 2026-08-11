import Foundation
import FerventioDomain

public struct BackendClient: Sendable {
    public struct DeviceCredentials: Sendable {
        public let installationID: String
        public let deviceSecret: String

        public init(installationID: String, deviceSecret: String) {
            self.installationID = installationID
            self.deviceSecret = deviceSecret
        }
    }

    public enum Error: Swift.Error, Equatable {
        case invalidResponse
        case httpStatus(Int)
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    public func get<Response: Decodable & Sendable>(
        _ path: String,
        sessionToken: String? = nil,
        deviceCredentials: DeviceCredentials? = nil,
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let sessionToken {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        if let deviceCredentials {
            request.setValue(deviceCredentials.installationID, forHTTPHeaderField: "X-Installation-ID")
            request.setValue(deviceCredentials.deviceSecret, forHTTPHeaderField: "X-Device-Secret")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Error.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }
}
