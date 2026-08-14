import Foundation
import FerventioDomain
import Testing
@testable import Ferventio

struct FfzModifierVisualEffectsTests {
    @Test
    func detectsOnlyAnimatedEffects() {
        #expect(FfzModifierVisualEffects.needsAnimation([.rotate]))
        #expect(FfzModifierVisualEffects.needsAnimation([.bounce, .flipX]))
        #expect(!FfzModifierVisualEffects.needsAnimation([.flipX, .noSpace]))
    }

    @Test
    func samplesRotateAndRainbowDurations() {
        let rotate = FfzModifierVisualEffects.state(
            effects: [.rotate],
            at: Date(timeIntervalSinceReferenceDate: 0.75)
        )
        let rainbow = FfzModifierVisualEffects.state(
            effects: [.rainbow],
            at: Date(timeIntervalSinceReferenceDate: 1)
        )

        #expect(abs(rotate.rotationDegrees - 180) < 0.001)
        #expect(abs(rainbow.hueRotationDegrees - 180) < 0.001)
    }

    @Test
    func samplesAppearAndCombinedLeaveKeyframes() {
        let appear = FfzModifierVisualEffects.state(
            effects: [.appear],
            at: Date(timeIntervalSinceReferenceDate: 0.75)
        )
        let leave = FfzModifierVisualEffects.state(
            effects: [.appear, .leave],
            at: Date(timeIntervalSinceReferenceDate: 4.5)
        )

        #expect(abs(appear.scaleX - 0.2) < 0.001)
        #expect(abs(appear.scaleY - 0.2) < 0.001)
        #expect(abs(appear.offsetX + 16) < 0.001)
        #expect(abs(appear.offsetY - 0.6) < 0.001)

        #expect(abs(leave.scaleX + 0.7) < 0.001)
        #expect(abs(leave.scaleY - 0.7) < 0.001)
        #expect(abs(leave.offsetX + 4) < 0.001)
        #expect(abs(leave.offsetY + 3) < 0.001)
    }

    @Test
    func samplesJamBounceAndShakeKeyframes() {
        let jam = FfzModifierVisualEffects.state(
            effects: [.jam],
            at: Date(timeIntervalSinceReferenceDate: 0.3)
        )
        let bounce = FfzModifierVisualEffects.state(
            effects: [.bounce],
            at: Date(timeIntervalSinceReferenceDate: 0.25)
        )
        let shake = FfzModifierVisualEffects.state(
            effects: [.shake],
            at: Date(timeIntervalSinceReferenceDate: 0.03)
        )

        #expect(abs(jam.offsetX - 2) < 0.001)
        #expect(abs(jam.offsetY - 4) < 0.001)
        #expect(abs(jam.rotationDegrees - 3) < 0.001)

        #expect(abs(bounce.scaleX + 0.8) < 0.001)
        #expect(abs(bounce.scaleY - 1) < 0.001)
        #expect(bounce.usesBottomAnchor)

        #expect(abs(shake.offsetX - 3) < 0.001)
        #expect(abs(shake.offsetY - 2) < 0.001)
    }
}
