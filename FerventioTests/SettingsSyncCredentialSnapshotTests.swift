import FerventioDomain
import Testing
@testable import Ferventio

struct SettingsSyncCredentialSnapshotTests {
    @Test
    func credentialIsLoadedOnlyOnceAndRemainsPinned() throws {
        let firstCredential = credential(token: "first-session")
        let secondCredential = credential(token: "second-session")
        var loadCount = 0

        let snapshot = SettingsSyncCredentialSnapshot {
            loadCount += 1
            let selected = loadCount == 1 ? firstCredential : secondCredential
            return StoredAuthentication(
                backendCredential: selected,
                accessLease: nil
            )
        }

        #expect(try snapshot.requireCredential() == firstCredential)
        #expect(try snapshot.requireCredential() == firstCredential)
        #expect(loadCount == 1)
    }

    @Test
    func missingAuthenticationRemainsUnauthenticated() {
        var loadCount = 0
        let snapshot = SettingsSyncCredentialSnapshot {
            loadCount += 1
            return nil
        }

        #expect(throws: SettingsSyncServiceError.notAuthenticated) {
            try snapshot.requireCredential()
        }
        #expect(throws: SettingsSyncServiceError.notAuthenticated) {
            try snapshot.requireCredential()
        }
        #expect(loadCount == 1)
    }

    private func credential(token: String) -> BackendSessionCredential {
        BackendSessionCredential(
            serverURL: "https://ferventio.godive.dev",
            token: token,
            expiresAtEpochMilliseconds: 200_000
        )
    }
}
