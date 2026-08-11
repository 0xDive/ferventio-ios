import Foundation

struct AppConfiguration: Sendable {
    let backendURL: URL
    let oauthCallbackScheme: String
    let oauthCallbackURL: URL
    let keychainService: String

    static let live: AppConfiguration = {
        #if DEBUG
        let callbackScheme = "io.ferventio.ios.debug"
        #else
        let callbackScheme = "io.ferventio.ios"
        #endif
        return AppConfiguration(
            backendURL: URL(string: "https://ferventio.godive.dev")!,
            oauthCallbackScheme: callbackScheme,
            oauthCallbackURL: URL(string: "\(callbackScheme)://oauth/callback")!,
            keychainService: "\(callbackScheme).secure"
        )
    }()
}
