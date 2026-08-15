import Foundation
import Testing
import UIKit
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

    @Test
    func oversizedDeclaredResponseIsRejectedBeforeDecode() async {
        let pipeline = makePipeline(
            data: Self.animatedGIF,
            contentLength: 8 * 1024 * 1024 + 1
        )

        let asset = await pipeline.image(
            for: URL(string: "https://example.com/oversized.gif")!,
            allowsAnimation: false
        )

        #expect(asset == nil)
        #expect(StubChatImageURLProtocol.requestCount == 1)
    }

    @Test
    func clearingCacheRejectsStaleInFlightCompletion() async throws {
        let staleAsset = ChatImageAsset(image: UIImage(), decodedByteCost: 1)
        let freshAsset = ChatImageAsset(image: UIImage(), decodedByteCost: 1)
        let loader = BlockingChatImageLoader(
            staleAsset: staleAsset,
            freshAsset: freshAsset
        )
        let pipeline = makePipeline(loader: { url, session, displayScale, allowsAnimation in
            await loader.load(
                url: url,
                session: session,
                displayScale: displayScale,
                allowsAnimation: allowsAnimation
            )
        })
        let url = URL(string: "https://example.com/stale-cache.gif")!

        let staleTask = Task { @MainActor in
            await pipeline.image(for: url, allowsAnimation: false)
        }
        await loader.waitUntilFirstLoadStarts()

        pipeline.removeAllCachedImages()
        await loader.completeFirstLoad()
        #expect(await staleTask.value === staleAsset)

        let fresh = try #require(
            await pipeline.image(for: url, allowsAnimation: false)
        )
        let cached = try #require(
            await pipeline.image(for: url, allowsAnimation: false)
        )

        #expect(fresh === freshAsset)
        #expect(cached === freshAsset)
        #expect(await loader.recordedCallCount() == 2)
    }

    private func makePipeline(
        data: Data,
        contentLength: Int? = nil
    ) -> ChatImagePipeline {
        StubChatImageURLProtocol.reset(
            data: data,
            contentLength: contentLength
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubChatImageURLProtocol.self]
        return ChatImagePipeline(session: URLSession(configuration: configuration))
    }

    private func makePipeline(loader: @escaping ChatImagePipeline.Loader) -> ChatImagePipeline {
        ChatImagePipeline(
            session: URLSession(configuration: .ephemeral),
            loader: loader
        )
    }
}

private actor BlockingChatImageLoader {
    private let staleAsset: ChatImageAsset
    private let freshAsset: ChatImageAsset
    private var calls = 0
    private var firstLoadStarted = false
    private var firstLoadWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstLoadContinuation: CheckedContinuation<ChatImageAsset?, Never>?

    init(staleAsset: ChatImageAsset, freshAsset: ChatImageAsset) {
        self.staleAsset = staleAsset
        self.freshAsset = freshAsset
    }

    func load(
        url: URL,
        session: URLSession,
        displayScale: CGFloat,
        allowsAnimation: Bool
    ) async -> ChatImageAsset? {
        calls += 1
        guard calls == 1 else {
            return freshAsset
        }

        return await withCheckedContinuation { continuation in
            firstLoadContinuation = continuation
            firstLoadStarted = true
            let waiters = firstLoadWaiters
            firstLoadWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilFirstLoadStarts() async {
        guard !firstLoadStarted else {
            return
        }
        await withCheckedContinuation { continuation in
            firstLoadWaiters.append(continuation)
        }
    }

    func completeFirstLoad() {
        firstLoadContinuation?.resume(returning: staleAsset)
        firstLoadContinuation = nil
    }

    func recordedCallCount() -> Int {
        calls
    }
}

private final class StubChatImageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responseData = Data()
    nonisolated(unsafe) private static var declaredContentLength: Int?
    nonisolated(unsafe) private static var requests = 0

    static func reset(data: Data, contentLength: Int? = nil) {
        lock.lock()
        responseData = data
        declaredContentLength = contentLength
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
        let contentLength = Self.declaredContentLength
        Self.requests += 1
        Self.lock.unlock()

        var headers = ["Content-Type": "image/gif"]
        if let contentLength {
            headers["Content-Length"] = String(contentLength)
        }

        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: headers
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
