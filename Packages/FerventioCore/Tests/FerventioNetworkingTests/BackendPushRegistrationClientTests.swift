import Foundation
import FerventioDomain
import Testing
@testable import FerventioNetworking

@Suite(.serialized)
struct BackendPushRegistrationClientTests {
    @Test
    func registrationBodyUsesIOSAPNsContractAndNormalizesLists() throws {
        let client = BackendPushRegistrationClient(
            baseURL: URL(string: "https://ferventio.example")!
        )
        let body = try client.makeRegistrationBody(
            BackendAPNsRegistration(
                deviceToken: " abc123 ",
                appVersion: " 0.1.0 ",
                channelIDs: ["100", "100", " 200 "],
                moderatorChannelIDs: ["200", "200"],
                notificationRules: ["reply", "mention", "reply"],
                highlightPhrases: [" Important ", "important"],
                selectedUserLogins: ["Streamer", "streamer"]
            ),
            device: device
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        #expect(object["installationId"] as? String == "installation")
        #expect(object["deviceSecret"] as? String == "device-secret")
        #expect(object["provider"] as? String == "apns")
        #expect(object["platform"] as? String == "ios")
        #expect(object["apnsDeviceToken"] as? String == "abc123")
        #expect(object["appVersion"] as? String == "0.1.0")
        #expect(object["channelIds"] as? [String] == ["100", "200"])
        #expect(object["moderatorChannelIds"] as? [String] == ["200"])
        #expect(object["notificationRules"] as? [String] == ["reply", "mention"])
        #expect(object["highlightPhrases"] as? [String] == ["Important"])
        #expect(object["selectedUserLogins"] as? [String] == ["Streamer"])
    }

    @Test
    func registerAndSelfTestUseExpectedEndpoints() async throws {
        let state = PushURLProtocolState()
        let session = makeSession(state: state) { request in
            switch (request.httpMethod, request.url?.path) {
            case ("PUT", "/v1/push/registrations/installation"):
                return (200, Data("{\"status\":\"registered\"}".utf8))
            case ("POST", "/v1/push/registrations/installation/self-test"):
                return (202, Data())
            default:
                return (404, Data("{\"error\":\"unexpected\"}".utf8))
            }
        }
        let client = BackendPushRegistrationClient(
            baseURL: URL(string: "https://ferventio.example")!,
            session: session
        )

        try await client.registerAPNs(
            BackendAPNsRegistration(
                deviceToken: "abc123",
                appVersion: "0.1.0",
                channelIDs: ["100"],
                moderatorChannelIDs: ["100"],
                notificationRules: ["reply"]
            ),
            device: device
        )
        try await client.selfTest(device: device)

        let requests = state.requests
        #expect(requests.count == 2)
        #expect(requests[0].httpMethod == "PUT")
        #expect(requests[1].httpMethod == "POST")
        #expect(requests[1].value(forHTTPHeaderField: "X-Device-Secret") == "device-secret")
    }

    @Test
    func deleteTreatsMissingRegistrationAsAlreadyDeleted() async throws {
        let state = PushURLProtocolState()
        let session = makeSession(state: state) { _ in
            (404, Data("{\"error\":\"registration not found\"}".utf8))
        }
        let client = BackendPushRegistrationClient(
            baseURL: URL(string: "https://ferventio.example")!,
            session: session
        )

        try await client.delete(device: device)
        let request = try #require(state.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "X-Device-Secret") == "device-secret")
    }

    private var device: DeviceIdentity {
        DeviceIdentity(
            installationID: "installation",
            deviceSecret: "device-secret"
        )
    }

    private func makeSession(
        state: PushURLProtocolState,
        handler: @escaping @Sendable (URLRequest) -> (Int, Data)
    ) -> URLSession {
        state.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PushRegistrationURLProtocol.self]
        PushRegistrationURLProtocol.state = state
        return URLSession(configuration: configuration)
    }
}

private final class PushURLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHandler: (@Sendable (URLRequest) -> (Int, Data))?
    private var storedRequests: [URLRequest] = []

    var handler: (@Sendable (URLRequest) -> (Int, Data))? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    var requests: [URLRequest] {
        lock.withLock { storedRequests }
    }

    func handle(_ request: URLRequest) -> (Int, Data)? {
        let handler = lock.withLock {
            storedRequests.append(request)
            return storedHandler
        }
        return handler?(request)
    }
}

private final class PushRegistrationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var state: PushURLProtocolState?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let result = Self.state?.handle(request),
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: result.0,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !result.1.isEmpty {
            client?.urlProtocol(self, didLoad: result.1)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
