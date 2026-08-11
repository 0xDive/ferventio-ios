import FerventioDomain
import SwiftUI

struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        Group {
            switch environment.state {
            case .launching:
                ProgressView()
            case .signedOut:
                ContentUnavailableView(
                    String(localized: "auth.signed_out.title"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("auth.signed_out.message")
                )
            case .signedIn:
                Text("app.title")
            }
        }
        .navigationTitle(Text("app.title"))
    }
}
