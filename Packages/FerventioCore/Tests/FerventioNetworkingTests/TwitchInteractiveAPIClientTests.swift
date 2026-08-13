import Foundation
import Testing
@testable import FerventioNetworking

struct TwitchInteractiveAPIClientTests {
    @Test
    func buildsBroadcasterPollRequest() throws {
        let request = try TwitchInteractiveAPIClient.makePollRequest(
            clientID: "client-1",
            accessToken: "access-1",
            broadcasterID: "broadcaster-1"
        )

        #expect(request.httpMethod == "GET")
        #expect(request.url?.host == "api.twitch.tv")
        #expect(request.url?.path == "/helix/polls")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(request.value(forHTTPHeaderField: "Client-Id") == "client-1")

        let components = try #require(
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        )
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        #expect(query["broadcaster_id"] == "broadcaster-1")
        #expect(query["first"] == "20")
    }

    @Test
    func buildsBroadcasterPredictionRequest() throws {
        let request = try TwitchInteractiveAPIClient.makePredictionRequest(
            clientID: "client-1",
            accessToken: "access-1",
            broadcasterID: "broadcaster-1"
        )

        #expect(request.url?.path == "/helix/predictions")
        #expect(request.httpMethod == "GET")
    }

    @Test
    func loadsLatestActivePollAndComputesEndTime() async throws {
        let client = TwitchInteractiveAPIClient(session: Self.makeSession { request in
            #expect(request.url?.path == "/helix/polls")
            return Self.response(
                for: request,
                json: """
                {
                  "data": [
                    {
                      "id": "old-poll",
                      "broadcaster_id": "broadcaster-1",
                      "title": "Old",
                      "choices": [],
                      "bits_voting_enabled": false,
                      "bits_per_vote": 0,
                      "channel_points_voting_enabled": false,
                      "channel_points_per_vote": 0,
                      "status": "COMPLETED",
                      "duration": 60,
                      "started_at": "2026-08-13T15:00:00Z",
                      "ended_at": "2026-08-13T15:01:00Z"
                    },
                    {
                      "id": "active-poll",
                      "broadcaster_id": "broadcaster-1",
                      "title": "Choose",
                      "choices": [
                        {
                          "id": "choice-1",
                          "title": "One",
                          "votes": 7,
                          "channel_points_votes": 2,
                          "bits_votes": 0
                        }
                      ],
                      "bits_voting_enabled": false,
                      "bits_per_vote": 0,
                      "channel_points_voting_enabled": true,
                      "channel_points_per_vote": 100,
                      "status": "ACTIVE",
                      "duration": 120,
                      "started_at": "2026-08-13T16:00:00Z",
                      "ended_at": null
                    }
                  ],
                  "pagination": {}
                }
                """
            )
        })

        let poll = try #require(
            try await client.loadActivePoll(
                clientID: "client-1",
                accessToken: "access-1",
                broadcasterID: "broadcaster-1"
            )
        )

        #expect(poll.id == "active-poll")
        #expect(poll.status == .active)
        #expect(poll.channelPointsVotingEnabled)
        #expect(poll.channelPointsPerVote == 100)
        #expect(poll.choices.first?.votes == 7)
        #expect(poll.endsAtMilliseconds == poll.startedAtMilliseconds + 120_000)
    }

    @Test
    func loadsLockedPredictionAndIgnoresResolvedHistory() async throws {
        let client = TwitchInteractiveAPIClient(session: Self.makeSession { request in
            Self.response(
                for: request,
                json: """
                {
                  "data": [
                    {
                      "id": "resolved",
                      "broadcaster_id": "broadcaster-1",
                      "title": "Resolved",
                      "winning_outcome_id": "outcome-a",
                      "outcomes": [],
                      "prediction_window": 60,
                      "status": "RESOLVED",
                      "created_at": "2026-08-13T14:00:00Z",
                      "ended_at": "2026-08-13T14:02:00Z",
                      "locked_at": "2026-08-13T14:01:00Z"
                    },
                    {
                      "id": "locked",
                      "broadcaster_id": "broadcaster-1",
                      "title": "Winner?",
                      "winning_outcome_id": null,
                      "outcomes": [
                        {
                          "id": "outcome-a",
                          "title": "A",
                          "users": 4,
                          "channel_points": 1500,
                          "color": "BLUE"
                        },
                        {
                          "id": "outcome-b",
                          "title": "B",
                          "users": 3,
                          "channel_points": 900,
                          "color": "PINK"
                        }
                      ],
                      "prediction_window": 90,
                      "status": "LOCKED",
                      "created_at": "2026-08-13T16:00:00Z",
                      "ended_at": null,
                      "locked_at": "2026-08-13T16:01:20Z"
                    }
                  ],
                  "pagination": {}
                }
                """
            )
        })

        let prediction = try #require(
            try await client.loadActivePrediction(
                clientID: "client-1",
                accessToken: "access-1",
                broadcasterID: "broadcaster-1"
            )
        )

        #expect(prediction.id == "locked")
        #expect(prediction.status == .locked)
        #expect(prediction.totalUsers == 7)
        #expect(prediction.totalChannelPoints == 2_400)
        #expect(prediction.outcomes.first?.color == .blue)
        #expect(prediction.locksAtMilliseconds == prediction.startedAtMilliseconds + 90_000)
    }

    @Test
    func returnsNilWhenNoCurrentInteractiveStateExists() async throws {
        let session = Self.makeSession { request in
            Self.response(
                for: request,
                json: "{\"data\":[],\"pagination\":{}}"
            )
        }
        let client = TwitchInteractiveAPIClient(session: session)

        let poll = try await client.loadActivePoll(
            clientID: "client",
            accessToken: "token",
            broadcasterID: "broadcaster"
        )
        let prediction = try await client.loadActivePrediction(
            clientID: "client",
            accessToken: "token",
            broadcasterID: "broadcaster"
        )

        #expect(poll == nil)
        #expect(prediction == nil)
    }

    @Test
    func rejectsBlankBroadcasterID() {
        #expect(throws: TwitchInteractiveAPIClient.Error.invalidArgument("broadcasterID")) {
            try TwitchInteractiveAPIClient.makePollRequest(
                clientID: "client",
                accessToken: "token",
                broadcasterID: "  "
            )
        }
    }

    private static func makeSession(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        InteractiveURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InteractiveURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        json: String
    ) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(json.utf8))
    }
}

private final class InteractiveURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
