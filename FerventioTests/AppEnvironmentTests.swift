import Testing
@testable import Ferventio

@MainActor
struct AppEnvironmentTests {
    @Test
    func startMovesApplicationToSignedOutState() {
        let environment = AppEnvironment()
        environment.start()
        #expect(environment.state == .signedOut)
    }
}
