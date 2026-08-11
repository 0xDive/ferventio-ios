import SwiftUI

@main
struct FerventioApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .task {
                    await environment.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    Task {
                        switch phase {
                        case .active:
                            await environment.applicationDidBecomeActive()
                        case .background:
                            await environment.applicationDidEnterBackground()
                        case .inactive:
                            break
                        @unknown default:
                            break
                        }
                    }
                }
        }
    }
}
