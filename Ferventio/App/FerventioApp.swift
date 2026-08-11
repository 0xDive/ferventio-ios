import SwiftUI

@main
struct FerventioApp: App {
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .task {
                    environment.start()
                }
        }
    }
}
