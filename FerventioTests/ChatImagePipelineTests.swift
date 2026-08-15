import Foundation
import Testing
@testable import Ferventio

@MainActor
struct ChatImagePipelineTests {
    private static let animatedGIF = Data(
        base64Encoded: "R0lGODlhAgACAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQICgAAACwAAAAAAgACAAAIBgABCAQQEAAh+QQICgAAACwAAAAAAgACAIEA/wAAAAAAAAAAAAAIBgABCAQQEAA7"
    )!

    @Test
    func reducedMotionDecodesOnlyTheFirstFrame() async throws {
        let pipeline = makePipeline(data: Self.animatedGIF)
        let asset = try #require(
            await pipeline.image(
                for: URL(string: "https://example.com/reduced-motion.gif")!,
                allowsAnimation: false
            )
        )

        #expect(asset.image.images == nil)
        #expect(StubChatImageURLProtocol.requestCount == 1)
    }

    @Test
    func animationPolicyUsesDistinctCacheEntries() async throws {
        let pipeline = makePipeline(data: Self.animatedGIF)
        let url = URL(string: "https://example.com/policy.gif")!

        let staticAsset = try #require(
            await pipeline.image(for: url, allowsAnimation: false)
        )
        let animatedAsset = try #require(
            await pipeline.image(for: url, allowsAnimation: true)
        )

        #expect(staticAsset.image.images == nil)
        #expect(animatedAsset.image.images?.count == 2)
        #expect(StubChatImageURLProtocol.requestCount == 2)
    }

    @Test
    func identicalRequestsReuseTheMemoryCache() async throws {
        let pipeline = makePipeline(data: Self.animatedGIF)
        let url = URL(string: "https://example.com/cache.gif")!

        let first = try #require(
            await pipeline.image(for: url, allowsAnimation: false)
        )
        let second = try #require(
            await pipeline.image(for: url, allowsAnimation: false)
        )

        #expect(first === second)
        #expect(StubChatImageURLProtocol.requestCount == 1)
    }

    @Test
    func concurrentIdenticalRequestsShareOneNetworkLoad() async throws {
        let pipeline = makePipeline(data: Self.animatedGIF)
        let url = URL(string: "https://example.com/coalesced.gif")!

        async let first = pipeline.image(for: url, allowsAnimation: true)
        async let second = pipeline.image(for: url, allowsAnimation: true)
        let assets = await (first, second)

        let firstAsset = try #require(assets.0)
        let secondAsset = try #require(assets.1)
        #expect(firstAsset === secondAsset)
        #expect(StubChatImageURLProtocol.requestCount == 1)
    }

    private func makePipeline(data: Data) -> ChatImagePipeline {
        StubChatImageURLProtocol.reset(data: data)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubChatImageURLProtocol.self]
        return ChatImagePipeline(session: URLSession(configuration: configuration))
    }
}

private final class StubChatImageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responseData = Data()
    nonisolated(unsafe) private static var requests = 0

    static func reset(data: Data) {
        lock.lock()
        responseData = data
        requests = 0
        lock.unlock()
    }

    static var requestCount: Int {
        lock.lock()
        let value = requests
        lock.unlock()
        return value
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let data = Self.responseData
        Self.requests += 1
        Self.lock.unlock()

        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "image/gif"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
