import Testing
@testable import FerventioDomain

struct AppStateTests {
    @Test
    func appStatesRemainDistinct() {
        #expect(AppState.launching != .signedOut)
        #expect(AppState.signedOut != .signedIn)
    }
}
