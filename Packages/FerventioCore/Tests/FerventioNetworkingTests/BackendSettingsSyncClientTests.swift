import Foundation
import FerventioDomain
import Testing
@testable import FerventioNetworking

@Suite(.serialized)
struct BackendSettingsSyncClientTests {
    @Test
    func currentDecodesPortableSnapshotAndAuthenticatesRequest() async throws {
        let state = URLProtocolState()
        let session = makeSession(state: state) { request in
            let body = """
            {
              "revision": 7,
              "updatedAt": "2026-08-15T09:00:00Z",
              "updatedByInstallationId": "other-installation",
              "appVersion": "0.1.0",
              "contentHash": "\(String(repeating: "a", count: 64))",
              "payload": {
                "format": "ferventio-settings-backup",
                "formatVersion": 2,
                "appVersion": "0.1.0",
                "contentHash": "\(String(repeating: "a", count: 64))",
                "content": {"settings": {"themeMode": "DARK"}}
              }
            }
            """
            return (200, Data(body.utf8))
        }
        let client = BackendSettingsSyncClient(
            baseURL: URL(string: "https://ferventio.example")!,
            session: session
        )

        let snapshot = try await client.current(
            device: device,
            credential: credential
        )

        #expect(snapshot?.revision == 7)
        #expect(snapshot?.updatedByInstallationID == "other-installation")
        #expect(snapshot?.payloadJSON.contains("\"formatVersion\":2") == true)
        let request = state.lastRequest
        #expect(request?.url?.path == "/v1/sync/settings")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
        #expect(request?.value(forHTTPHeaderField: "X-Installation-ID") == "installation")
        #expect(request?.value(forHTTPHeaderField: "X-Device-Secret") == "device-secret")
    }

    @Test
    func putSurfacesRevisionConflictAndEncodesPayloadAsJSONObject() async throws {
        let state = URLProtocolState()
        let session = makeSession(state: state) { _ in
            let body = """
            {
              "error": "settings revision conflict",
              "snapshot": {
                "revision": 3,
                "updatedAt": "2026-08-15T09:00:00Z",
                "updatedByInstallationId": "remote-installation",
                "appVersion": "0.1.0",
                "contentHash": "\(String(repeating: "b", count: 64))",
                "payload": {
                  "format": "ferventio-settings-backup",
                  "formatVersion": 2,
                  "appVersion": "0.1.0",
                  "contentHash": "\(String(repeating: "b", count: 64))",
                  "content": {}
                }
              }
            }
            """
            return (409, Data(body.utf8))
        }
        let client = BackendSettingsSyncClient(
            baseURL: URL(string: "https://ferventio.example")!,
            session: session
        )
        let payload = """
        {
          "format": "ferventio-settings-backup",
          "formatVersion": 2,
          "appVersion": "0.1.0",
          "contentHash": "\(String(repeating: "c", count: 64))",
          "content": {}
        }
        """

        let requestBody = try client.makePutRequestBody(
            payloadJSON: payload,
            baseRevision: 2,
            force: false
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
        )
        #expect(object["baseRevision"] as? Int == 2)
        #expect(object["force"] as? Bool == false)
        let encodedPayload = try #require(object["payload"] as? [String: Any])
        #expect(encodedPayload["formatVersion"] as? Int == 2)

        do {
            _ = try await client.put(
                payloadJSON: payload,
                baseRevision: 2,
                force: false,
                device: device,
                credential: credential
            )
            Issue.record("Expected settings revision conflict")
        } catch let BackendSettingsSyncError.conflict(snapshot) {
            #expect(snapshot.revision == 3)
            #expect(snapshot.updatedByInstallationID == "remote-installation")
        }

        let request = try #require(state.lastRequest)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/v1/sync/settings")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
    }

    @Test
    func historyDecodesRevisionsAndAuthenticatesRequest() async throws {
        let state = URLProtocolState()
        let session = makeSession(state: state) { _ in
            let body = """
            {
              "data": [
                {
                  "revision": 5,
                  "updatedAt": "2026-08-15T10:00:00Z",
                  "updatedByInstallationId": "installation",
                  "appVersion": "0.1.0",
                  "contentHash": "\(String(repeating: "d", count: 64))"
                },
                {
                  "revision": 4,
                  "updatedAt": "2026-08-15T09:00:00Z",
                  "updatedByInstallationId": "other-installation",
                  "appVersion": null,
                  "contentHash": "\(String(repeating: "e", count: 64))"
                }
              ]
            }
            """
            return (200, Data(body.utf8))
        }
        let client = BackendSettingsSyncClient(
            baseURL: URL(string: "https://ferventio.example")!,
            session: session
        )

        let entries = try await client.history(
            device: device,
            credential: credential
        )

        #expect(entries.map(\.revision) == [5, 4])
        #expect(entries[0].appVersion == "0.1.0")
        #expect(entries[1].updatedByInstallationID == "other-installation")
        let request = try #require(state.lastRequest)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/sync/settings/history")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
        #expect(request.value(forHTTPHeaderField: "X-Installation-ID") == "installation")
        #expect(request.value(forHTTPHeaderField: "X-Device-Secret") == "device-secret")
    }

    @Test
    func restorePostsSelectedRevisionAndDecodesNewSnapshot() async throws {
        let state = URLProtocolState()
        let session = makeSession(state: state) { _ in
            let body = """
            {
              "revision": 8,
              "updatedAt": "2026-08-15T11:00:00Z",
              "updatedByInstallationId": "installation",
              "appVersion": "0.1.0",
              "contentHash": "\(String(repeating: "f", count: 64))",
              "payload": {
                "format": "ferventio-settings-backup",
                "formatVersion": 2,
                "appVersion": "0.1.0",
                "contentHash": "\(String(repeating: "f", count: 64))",
                "content": {"settings": {"themeMode": "LIGHT"}}
              }
            }
            """
            return (200, Data(body.utf8))
        }
        let client = BackendSettingsSyncClient(
            baseURL: URL(string: "https://ferventio.example")!,
            session: session
        )

        let snapshot = try await client.restore(
            revision: 4,
            device: device,
            credential: credential
        )

        #expect(snapshot.revision == 8)
        #expect(snapshot.payloadJSON.contains("\"formatVersion\":2") == true)
        let request = try #require(state.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/sync/settings/restore/4")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer session-token")
    }

    private var device: DeviceIdentity {
        DeviceIdentity(
            installationID: "installation",
            deviceSecret: "device-secret"
        )
    }

    private var credential: BackendSessionCredential {
        BackendSessionCredential(
            serverURL: "https://ferventio.example",
            token: "session-token",
            expiresAtEpochMilliseconds: Int64.max
        )
    }

    private func makeSession(
        state: URLProtocolState,
        handler: @escaping @Sendable (URLRequest) -> (Int, Data)
    ) -> URLSession {
        state.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsSyncURLProtocol.self]
        SettingsSyncURLProtocol.state = state
        return URLSession(configuration: configuration)
    }
}

private final class URLProtocolState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHandler: (@Sendable (URLRequest) -> (Int, Data))?
    private var storedLastRequest: URLRequest?

    var handler: (@Sendable (URLRequest) -> (Int, Data))? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    var lastRequest: URLRequest? {
        lock.withLock { storedLastRequest }
    }

    func handle(_ request: URLRequest) -> (Int, Data)? {
        let handler = lock.withLock {
            storedLastRequest = request
            return storedHandler
        }
        return handler?(request)
    }
}

private final class SettingsSyncURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var state: URLProtocolState?

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
        client?.urlProtocol(self, didLoad: result.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
