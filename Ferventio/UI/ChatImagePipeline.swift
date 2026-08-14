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
    private let cache = NSCache<NSURL, ChatImageAsset>()
    private let session: URLSession

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

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("image/avif,image/webp,image/gif,image/png,image/*;q=0.8", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= Self.maximumResponseBytes,
                  let asset = Self.decode(data) else {
                return nil
            }
            cache.setObject(asset, forKey: url as NSURL, cost: asset.decodedByteCost)
            return asset
        } catch {
            return nil
        }
    }

    func removeAllCachedImages() {
        cache.removeAllObjects()
    }

    private static func decode(_ data: Data) -> ChatImageAsset? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data).map { ChatImageAsset(image: $0, decodedByteCost: data.count) }
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return UIImage(data: data).map { ChatImageAsset(image: $0, decodedByteCost: data.count) }
            }
            let image = UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up)
            let cost = max(1, cgImage.width * cgImage.height * 4)
            return ChatImageAsset(image: image, decodedByteCost: cost)
        }

        var frames: [UIImage] = []
        frames.reserveCapacity(frameCount)
        var duration: TimeInterval = 0
        var cost = 0

        for index in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }
            frames.append(UIImage(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .up))
            duration += frameDuration(source: source, index: index)
            cost += max(1, cgImage.width * cgImage.height * 4)
        }

        guard let first = frames.first else {
            return nil
        }
        if duration <= 0 {
            duration = Double(frames.count) * 0.1
        }
        let animated = UIImage.animatedImage(with: frames, duration: duration) ?? first
        return ChatImageAsset(image: animated, decodedByteCost: max(cost, data.count))
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
