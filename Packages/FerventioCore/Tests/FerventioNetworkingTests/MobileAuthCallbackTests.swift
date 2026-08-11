import Foundation
import Testing
@testable import FerventioNetworking

struct MobileAuthCallbackTests {
    @Test
    func parsesExpectedHandoff() throws {
        let url = URL(string: "io.ferventio.ios://oauth/callback?state=state-1&code=handoff-1")!

        let handoff = try MobileAuthCallback.parse(
            url,
            expectedScheme: "io.ferventio.ios",
            expectedState: "state-1"
        )

        #expect(handoff.code == "handoff-1")
        #expect(handoff.state == "state-1")
    }

    @Test
    func rejectsMismatchedState() {
        let url = URL(string: "io.ferventio.ios://oauth/callback?state=other&code=handoff-1")!

        #expect(throws: MobileAuthCallback.Error.stateMismatch) {
            try MobileAuthCallback.parse(
                url,
                expectedScheme: "io.ferventio.ios",
                expectedState: "state-1"
            )
        }
    }

    @Test
    func surfacesBackendAuthorizationError() {
        let url = URL(string: "io.ferventio.ios://oauth/callback?state=state-1&error=access_denied")!

        #expect(throws: MobileAuthCallback.Error.authorizationDenied("access_denied")) {
            try MobileAuthCallback.parse(
                url,
                expectedScheme: "io.ferventio.ios",
                expectedState: "state-1"
            )
        }
    }

    @Test
    func rejectsUnexpectedCallbackOrigin() {
        let url = URL(string: "evil.ferventio://oauth/callback?state=state-1&code=handoff-1")!

        #expect(throws: MobileAuthCallback.Error.invalidURL) {
            try MobileAuthCallback.parse(
                url,
                expectedScheme: "io.ferventio.ios",
                expectedState: "state-1"
            )
        }
    }
}
