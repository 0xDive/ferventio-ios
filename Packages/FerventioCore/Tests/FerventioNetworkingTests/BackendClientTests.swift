import Foundation
import Testing
@testable import FerventioNetworking

struct BackendClientTests {
    @Test
    func deviceCredentialsPreserveIdentity() {
        let credentials = BackendClient.DeviceCredentials(
            installationID: "installation",
            deviceSecret: "secret"
        )
        #expect(credentials.installationID == "installation")
        #expect(credentials.deviceSecret == "secret")
    }
}
