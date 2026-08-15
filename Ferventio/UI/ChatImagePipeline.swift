import Foundation
import ImageIO
import SwiftUI
import UIKit

final class ChatImageAsset: NSObject, @unchecked Sendable {
    let image: UIImage
    let decodedByteCost: Int

    init(image: UIImage, decodedByteCost: Int) {
        self.image = image
        self.decodedByteCost = decodedByteCost
    }
}

private enum ChatImageLoader {
    private static let maximumResponseBytes = 8 * 1024 * 1024

    // Chat emotes render at 28pt, or up to 112pt with wide modifiers.
    // 336px exactly covers the 3x Retina wide case without retaining source-sized frames.
    private static let maximumDecodedPixelDimension = 336
    private static let maximumAnimatedDecodedBytes = 32 * 1024 * 1024
    private static let maximumAnimationFrames = 360

    static func load(
        url: URL,
        session: URLSession,
        displayScale: CGFloat,
        allowsAnimation: Bool
    ) async -> ChatImageAsset? {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(
                "image/avif,image/webp,image/gif,image/png,image/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            request.timeoutInterval = 20
            guard let (data, http) = try await boundedData(
                for: request,
                session: session
            ),
            (200..<300).contains(http.statusCode),
            !Task.isCancelled else {
                return nil
            }
            return decode(
                data,
                displayScale: displayScale,
                allowsAnimation: allowsAnimation
            )
        } catch {
            return nil
        }
    }

    private static func boundedData(
        for request: URLRequest,
        session: URLSession
    ) async throws -> (Data, HTTPURLResponse)? {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            return nil
        }

        let expectedLength = http.expectedContentLength
        guard expectedLength <= 0 || expectedLength <= Int64(maximumResponseBytes) else {
            return nil
        }

        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(Int(expectedLength))
        }

        for try await byte in bytes {
            guard !Task.isCancelled,
                  data.count < maximumResponseBytes else {
                return nil
            }
            data.append(byte)
        }
        return (data, http)
    }

    private static func decode(
        _ data: Data,
        displayScale: CGFloat,
        allowsAnimation: Bool
    ) -> ChatImageAsset? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
        ]
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            sourceOptions as CFDictionary
        ) else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0,
              let firstCGImage = decodedFrame(source: source, index: 0) else {
            return nil
        }

        let firstImage = UIImage(
            cgImage: firstCGImage,
            scale: displayScale,
            orientation: .up
        )
        let firstCost = decodedCost(of: firstCGImage)
        guard frameCount > 1, allowsAnimation else {
            return ChatImageAsset(
                image: firstImage,
                decodedByteCost: max(firstCost, data.count)
            )
        }
        guard frameCount <= maximumAnimationFrames else {
            return ChatImageAsset(
                image: firstImage,
                decodedByteCost: max(firstCost, data.count)
            )
        }

        var frames: [UIImage] = [firstImage]
        frames.reserveCapacity(min(frameCount, 64))
        var duration = frameDuration(source: source, index: 0)
        var cost = firstCost

        for index in 1..<frameCount {
            guard !Task.isCancelled else {
                return nil
            }
            guard let cgImage = decodedFrame(source: source, index: index) else {
                continue
            }
            let frameCost = decodedCost(of: cgImage)
            guard frameCost <= maximumAnimatedDecodedBytes - min(cost, maximumAnimatedDecodedBytes) else {
                return ChatImageAsset(
                    image: firstImage,
                    decodedByteCost: max(firstCost, data.count)
                )
            }

            frames.append(
                UIImage(
                    cgImage: cgImage,
                    scale: displayScale,
                    orientation: .up
                )
            )
            duration += frameDuration(source: source, index: index)
            cost += frameCost
        }

        if duration <= 0 {
            duration = Double(frames.count) * 0.1
        }
        let animated = UIImage.animatedImage(with: frames, duration: duration) ?? firstImage
        return ChatImageAsset(image: animated, decodedByteCost: max(cost, data.count))
    }

    private static func decodedFrame(
        source: CGImageSource,
        index: Int
    ) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDecodedPixelDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            index,
            options as CFDictionary
        )
    }

    private static func decodedCost(of image: CGImage) -> Int {
        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        return overflow ? maximumAnimatedDecodedBytes : max(1, cost)
    }

    private static func frameDuration(
        source: CGImageSource,
        index: Int
    ) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [AnyHashable: Any],
              let delay = findDelay(in: properties) else {
            return 0.1
        }
        if delay < 0.02 {
            return 0.1
        }
        return min(delay, 10)
    }

    private static func findDelay(in dictionary: [AnyHashable: Any]) -> TimeInterval? {
        for (key, value) in dictionary {
            let keyName = String(describing: key).lowercased()
            if keyName.contains("unclampeddelaytime") || keyName.hasSuffix("delaytime") {
                if let number = value as? NSNumber {
                    return number.doubleValue
                }
            }
            if let nested = value as? [AnyHashable: Any],
               let delay = findDelay(in: nested) {
                return delay
            }
            if let nested = value as? NSDictionary {
                var converted: [AnyHashable: Any] = [:]
                nested.forEach { key, value in
                    if let key = key as? AnyHashable {
                        converted[key] = value
                    }
                }
                if let delay = findDelay(in: converted) {
                    return delay
                }
            }
        }
        return nil
    }
}

@MainActor
final class ChatImagePipeline {
    typealias Loader = @Sendable (
        _ url: URL,
        _ session: URLSession,
        _ displayScale: CGFloat,
        _ allowsAnimation: Bool
    ) async -> ChatImageAsset?

    static let shared = ChatImagePipeline()

    private struct RequestKey: Hashable {
        let url: URL
        let allowsAnimation: Bool
    }

    private struct InFlightLoad {
        let id: UUID
        let task: Task<ChatImageAsset?, Never>
    }

    private let cache = NSCache<NSString, ChatImageAsset>()
    private let session: URLSession
    private let loader: Loader
    private var inFlight: [RequestKey: InFlightLoad] = [:]
    private var cacheGeneration: UInt64 = 0

    init(session: URLSession? = nil, loader: Loader? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.urlCache = URLCache(
                memoryCapacity: 32 * 1024 * 1024,
                diskCapacity: 128 * 1024 * 1024,
                diskPath: "ferventio-chat-images"
            )
            self.session = URLSession(configuration: configuration)
        }
        self.loader = loader ?? { url, session, displayScale, allowsAnimation in
            await ChatImageLoader.load(
                url: url,
                session: session,
                displayScale: displayScale,
                allowsAnimation: allowsAnimation
            )
        }
        cache.countLimit = 512
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL, allowsAnimation: Bool = true) async -> ChatImageAsset? {
        guard url.scheme?.lowercased() == "https" else {
            return nil
        }
        let requestKey = RequestKey(url: url, allowsAnimation: allowsAnimation)
        let cacheKey = cacheKey(for: requestKey)
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        if let load = inFlight[requestKey] {
            return await load.task.value
        }

        let loadID = UUID()
        let requestGeneration = cacheGeneration
        let displayScale = UIScreen.main.scale
        let task = Task { [session, loader] in
            await loader(url, session, displayScale, allowsAnimation)
        }
        inFlight[requestKey] = InFlightLoad(id: loadID, task: task)
        let asset = await task.value
        if inFlight[requestKey]?.id == loadID {
            inFlight[requestKey] = nil
        }

        if cacheGeneration == requestGeneration, let asset {
            cache.setObject(asset, forKey: cacheKey, cost: asset.decodedByteCost)
        }
        return asset
    }

    func removeAllCachedImages() {
        cacheGeneration &+= 1
        cache.removeAllObjects()
        for load in inFlight.values {
            load.task.cancel()
        }
        inFlight.removeAll()
    }

    private func cacheKey(for requestKey: RequestKey) -> NSString {
        "\(requestKey.url.absoluteString)#animation=\(requestKey.allowsAnimation)" as NSString
    }
}

struct ChatUIImageView: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = false
        return view
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        let displayedImage = reduceMotion ? (image.images?.first ?? image) : image
        if uiView.image !== displayedImage {
            uiView.stopAnimating()
            uiView.image = displayedImage
        }
        if !reduceMotion && image.images?.isEmpty == false {
            uiView.startAnimating()
        } else {
            uiView.stopAnimating()
        }
    }
}
