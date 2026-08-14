import Foundation
import FerventioDomain

struct FfzModifierVisualState: Equatable {
    var scaleX: Double
    var scaleY: Double
    var rotationDegrees: Double
    var offsetX: Double
    var offsetY: Double
    var hueRotationDegrees: Double
    var usesBottomAnchor: Bool

    static let identity = FfzModifierVisualState(
        scaleX: 1,
        scaleY: 1,
        rotationDegrees: 0,
        offsetX: 0,
        offsetY: 0,
        hueRotationDegrees: 0,
        usesBottomAnchor: false
    )

    mutating func combine(_ other: FfzModifierVisualState) {
        scaleX *= other.scaleX
        scaleY *= other.scaleY
        rotationDegrees += other.rotationDegrees
        offsetX += other.offsetX
        offsetY += other.offsetY
        hueRotationDegrees += other.hueRotationDegrees
        usesBottomAnchor = usesBottomAnchor || other.usesBottomAnchor
    }
}

enum FfzModifierVisualEffects {
    private struct Keyframe {
        let percent: Double
        let scaleX: Double
        let scaleY: Double
        let rotationDegrees: Double
        let offsetX: Double
        let offsetY: Double

        init(
            _ percent: Double,
            scaleX: Double = 1,
            scaleY: Double = 1,
            rotationDegrees: Double = 0,
            offsetX: Double = 0,
            offsetY: Double = 0
        ) {
            self.percent = percent
            self.scaleX = scaleX
            self.scaleY = scaleY
            self.rotationDegrees = rotationDegrees
            self.offsetX = offsetX
            self.offsetY = offsetY
        }
    }

    private static let animatedEffects: Set<BttvModifierEffect> = [
        .appear,
        .bounce,
        .jam,
        .leave,
        .rainbow,
        .rotate,
        .shake,
    ]

    static func needsAnimation(_ effects: Set<BttvModifierEffect>) -> Bool {
        !effects.isDisjoint(with: animatedEffects)
    }

    static func state(
        effects: Set<BttvModifierEffect>,
        at date: Date
    ) -> FfzModifierVisualState {
        var result = FfzModifierVisualState.identity

        if effects.contains(.rotate) {
            result.rotationDegrees += phase(at: date, duration: 1.5) * 360
        }
        if effects.contains(.rainbow) {
            result.hueRotationDegrees += phase(at: date, duration: 2) * 360
        }
        if effects.contains(.shake) {
            result.combine(sample(shakeFrames, at: date, duration: 0.1))
        }
        if effects.contains(.jam) {
            result.combine(sample(jamFrames, at: date, duration: 0.6))
        }
        if effects.contains(.bounce) {
            var bounce = sample(bounceFrames, at: date, duration: 0.5)
            bounce.usesBottomAnchor = true
            result.combine(bounce)
        }

        let appears = effects.contains(.appear)
        let leaves = effects.contains(.leave)
        if appears && leaves {
            let combinedPhase = phase(at: date, duration: 6)
            if combinedPhase < 0.5 {
                result.combine(sample(appearFrames, percent: combinedPhase * 200))
            } else {
                result.combine(sample(leaveFrames, percent: (combinedPhase - 0.5) * 200))
            }
        } else if appears {
            result.combine(sample(appearFrames, at: date, duration: 3))
        } else if leaves {
            result.combine(sample(leaveFrames, at: date, duration: 3))
        }

        return result
    }

    private static func phase(at date: Date, duration: TimeInterval) -> Double {
        let raw = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        let normalized = raw >= 0 ? raw : raw + duration
        return normalized / duration
    }

    private static func sample(
        _ frames: [Keyframe],
        at date: Date,
        duration: TimeInterval
    ) -> FfzModifierVisualState {
        sample(frames, percent: phase(at: date, duration: duration) * 100)
    }

    private static func sample(
        _ frames: [Keyframe],
        percent: Double
    ) -> FfzModifierVisualState {
        guard let first = frames.first else {
            return .identity
        }
        if percent <= first.percent {
            return state(for: first)
        }

        for index in 1..<frames.count {
            let upper = frames[index]
            guard percent <= upper.percent else {
                continue
            }
            let lower = frames[index - 1]
            let span = upper.percent - lower.percent
            guard span > 0 else {
                return state(for: upper)
            }
            let progress = (percent - lower.percent) / span
            return FfzModifierVisualState(
                scaleX: interpolate(lower.scaleX, upper.scaleX, progress),
                scaleY: interpolate(lower.scaleY, upper.scaleY, progress),
                rotationDegrees: interpolate(lower.rotationDegrees, upper.rotationDegrees, progress),
                offsetX: interpolate(lower.offsetX, upper.offsetX, progress),
                offsetY: interpolate(lower.offsetY, upper.offsetY, progress),
                hueRotationDegrees: 0,
                usesBottomAnchor: false
            )
        }
        return state(for: frames.last ?? first)
    }

    private static func state(for frame: Keyframe) -> FfzModifierVisualState {
        FfzModifierVisualState(
            scaleX: frame.scaleX,
            scaleY: frame.scaleY,
            rotationDegrees: frame.rotationDegrees,
            offsetX: frame.offsetX,
            offsetY: frame.offsetY,
            hueRotationDegrees: 0,
            usesBottomAnchor: false
        )
    }

    private static func interpolate(_ lower: Double, _ upper: Double, _ progress: Double) -> Double {
        lower + ((upper - lower) * progress)
    }

    private static let appearFrames: [Keyframe] = [
        Keyframe(0, scaleX: 0, scaleY: 0, offsetX: -18),
        Keyframe(19.99, scaleX: 0, scaleY: 0, offsetX: -18),
        Keyframe(20, scaleX: 0.1, scaleY: 0.1, offsetX: -18),
        Keyframe(25, scaleX: 0.2, scaleY: 0.2, offsetX: -16, offsetY: 0.6),
        Keyframe(30, scaleX: 0.3, scaleY: 0.3, offsetX: -14, offsetY: -4),
        Keyframe(35, scaleX: 0.4, scaleY: 0.4, offsetX: -12, offsetY: 0.6),
        Keyframe(40, scaleX: 0.5, scaleY: 0.5, offsetX: -10, offsetY: -4),
        Keyframe(45, scaleX: 0.6, scaleY: 0.6, offsetX: -8, offsetY: 2),
        Keyframe(50, scaleX: 0.7, scaleY: 0.7, offsetX: -6, offsetY: -3),
        Keyframe(55, scaleX: 0.8, scaleY: 0.8, offsetX: -4, offsetY: 2),
        Keyframe(60, scaleX: 0.9, scaleY: 0.9, offsetX: -2, offsetY: -3),
        Keyframe(65),
        Keyframe(100),
    ]

    private static let leaveFrames: [Keyframe] = [
        Keyframe(0),
        Keyframe(39.99),
        Keyframe(40, scaleX: -0.9, scaleY: 0.9, offsetY: -3),
        Keyframe(45, scaleX: -0.8, scaleY: 0.8, offsetX: -2, offsetY: 2),
        Keyframe(50, scaleX: -0.7, scaleY: 0.7, offsetX: -4, offsetY: -3),
        Keyframe(55, scaleX: -0.6, scaleY: 0.6, offsetX: -6, offsetY: 2),
        Keyframe(60, scaleX: -0.5, scaleY: 0.5, offsetX: -8, offsetY: -4),
        Keyframe(65, scaleX: -0.4, scaleY: 0.4, offsetX: -10, offsetY: 0.6),
        Keyframe(70, scaleX: -0.3, scaleY: 0.3, offsetX: -12, offsetY: -4),
        Keyframe(75, scaleX: -0.2, scaleY: 0.2, offsetX: -14, offsetY: 0.6),
        Keyframe(80, scaleX: -0.1, scaleY: 0.1, offsetX: -16),
        Keyframe(85, scaleX: -0.01, scaleY: 0, offsetX: -18),
        Keyframe(100, scaleX: 0, scaleY: 0, offsetX: -18),
    ]

    private static let shakeFrames: [Keyframe] = [
        Keyframe(0, offsetX: 1, offsetY: 1),
        Keyframe(10, offsetX: -1, offsetY: -2),
        Keyframe(20, offsetX: -3),
        Keyframe(30, offsetX: 3, offsetY: 2),
        Keyframe(40, offsetX: 1, offsetY: -1),
        Keyframe(50, offsetX: -1, offsetY: 2),
        Keyframe(60, offsetX: -3, offsetY: 1),
        Keyframe(70, offsetX: 3, offsetY: 1),
        Keyframe(80, offsetX: -1, offsetY: -1),
        Keyframe(90, offsetX: 1, offsetY: 2),
        Keyframe(100, offsetX: 1, offsetY: -2),
    ]

    private static let jamFrames: [Keyframe] = [
        Keyframe(0, rotationDegrees: -6, offsetX: -2, offsetY: -2),
        Keyframe(10, rotationDegrees: -8, offsetX: -1.5, offsetY: -2),
        Keyframe(20, rotationDegrees: -8, offsetX: 1, offsetY: -1.5),
        Keyframe(30, rotationDegrees: -6, offsetX: 3, offsetY: 2.5),
        Keyframe(40, rotationDegrees: -2, offsetX: 3, offsetY: 4),
        Keyframe(50, rotationDegrees: 3, offsetX: 2, offsetY: 4),
        Keyframe(60, rotationDegrees: 3, offsetX: 1, offsetY: 4),
        Keyframe(70, rotationDegrees: 2, offsetX: -0.5, offsetY: 3),
        Keyframe(80, offsetX: -1.25, offsetY: 1),
        Keyframe(90, rotationDegrees: -2, offsetX: -1.75, offsetY: -0.5),
        Keyframe(100, rotationDegrees: -5, offsetX: -2, offsetY: -2),
    ]

    private static let bounceFrames: [Keyframe] = [
        Keyframe(0, scaleX: 0.8, scaleY: 1),
        Keyframe(10, scaleX: 0.9, scaleY: 0.8),
        Keyframe(20, scaleX: 1, scaleY: 0.4),
        Keyframe(25, scaleX: 1.2, scaleY: 0.3),
        Keyframe(25.001, scaleX: -1.2, scaleY: 0.3),
        Keyframe(30, scaleX: -1, scaleY: 0.4),
        Keyframe(40, scaleX: -0.9, scaleY: 0.8),
        Keyframe(50, scaleX: -0.8, scaleY: 1),
        Keyframe(60, scaleX: -0.9, scaleY: 0.8),
        Keyframe(70, scaleX: -1, scaleY: 0.4),
        Keyframe(75, scaleX: -1.2, scaleY: 0.3),
        Keyframe(75.001, scaleX: 1.2, scaleY: 0.3),
        Keyframe(80, scaleX: 1, scaleY: 0.4),
        Keyframe(90, scaleX: 0.9, scaleY: 0.8),
        Keyframe(100, scaleX: 0.8, scaleY: 1),
    ]
}
