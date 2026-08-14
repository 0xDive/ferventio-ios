import Foundation
import ImageIO
import SwiftUI
import UIKit

@MainActor
final class ChatImageAsset: NSObject {
    let image: UIImage
    let decodedByteCost: Int

    init(image: UIImage, decodedByteCost: Int) {
        self.image = image
        self.decodedByteCost = decodedByteCost
    }
}

@MainActor
final class ChatImagePipeline {
    static let shared = ChatImagePipeline()

    private static let maximumResponseBytes = 8 * 1024 * 1024

    // Chat emotes render at 28pt, or up to 112pt with wide modifiers.
    // 384px covers the 3x Retina wide case without retaining source-sized frames.
    private static let maximumDecodedPixelDimension = 384
    private static let maximumAnimatedDecodedBytes = 32 * 1024 * 1024
    private static let maximumAnimationFrames = 360

    private let cache = NSCache<NSURL, ChatImageAsset>()
    private let session: URLSession
    private var inFlight: [URL: Task<ChatImageAsset?, Never>] = [:]

    init(session: URLSession? = nil) {
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
        cache.countLimit = 512
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL) async -> ChatImageAsset? {
        guard url.scheme?.lowercased() == "https" else {
            return nil
        }
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if let task = inFlight[url] {
            return await task.value
        }

        let task = Task { [session] in
            await Self.load(url: url, session: session)
        }
        inFlight[url] = task
        let asset = await task.value
        inFlight[url] = nil

        if let asset {
            cache.setObject(asset, forKey: url as NSURL, cost: asset.decodedByteCost)
        }
        return asset
    }

    func removeAllCachedImages() {
        cache.removeAllObjects()
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
    }

    private static func load(url: URL, session: URLSession) async -> ChatImageAsset? {
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(
                "image/avif,image/webp,image/gif,image/png,image/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= maximumResponseBytes else {
                return nil
            }
            return decode(data)
        } catch {
            return nil
        }
    }

    private static func decode(_ data: Data) -> ChatImageAsset? {
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
            scale: UIScreen.main.scale,
            orientation: .up
        )
        let firstCost = decodedCost(of: firstCGImage)
        guard frameCount > 1 else {
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
                    scale: UIScreen.main.scale,
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
