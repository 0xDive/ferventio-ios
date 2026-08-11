import FerventioDomain
import Observation

@MainActor
@Observable
final class AppEnvironment {
    var state: AppState = .launching

    func start() {
        state = .signedOut
    }
}
