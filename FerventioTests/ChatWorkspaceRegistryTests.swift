import Foundation
import Testing
@testable import Ferventio

@MainActor
struct ChatWorkspaceRegistryTests {
    @Test
    func openNormalizesLoginAndSelectsExistingWorkspaceWithoutDuplicating() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let store = ChatWorkspaceRegistryStore(persistence: harness.persistence)

        let first = try #require(openedWorkspace(store.open(login: "  SomeChannel  ")))
        let second = try #require(openedWorkspace(store.open(login: "SOMECHANNEL")))

        #expect(first.id == second.id)
        #expect(first.login == "somechannel")
        #expect(store.workspaces == [first])
        #expect(store.activeWorkspaceID == first.id)
    }

    @Test
    func capacityRejectsNewWorkspaceWithoutEvictingExistingState() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let store = ChatWorkspaceRegistryStore(persistence: harness.persistence)

        for index in 0..<ChatWorkspaceRegistryStore.maximumWorkspaces {
            #expect(openedWorkspace(store.open(login: "channel\(index)")) != nil)
        }
        let existing = store.workspaces
        let active = store.activeWorkspaceID

        #expect(store.open(login: "overflow") == .capacityReached)
        #expect(store.workspaces == existing)
        #expect(store.activeWorkspaceID == active)
    }

    @Test
    func closingActiveWorkspaceSelectsNearestRemainingNeighbor() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let store = ChatWorkspaceRegistryStore(persistence: harness.persistence)

        let first = try #require(openedWorkspace(store.open(login: "one")))
        let second = try #require(openedWorkspace(store.open(login: "two")))
        let third = try #require(openedWorkspace(store.open(login: "three")))

        #expect(store.select(id: second.id))
        #expect(store.close(id: second.id) == second)
        #expect(store.activeWorkspaceID == third.id)

        #expect(store.close(id: third.id) == third)
        #expect(store.activeWorkspaceID == first.id)

        #expect(store.close(id: first.id) == first)
        #expect(store.activeWorkspaceID == nil)
    }

    @Test
    func orderAndActiveSelectionRoundTripThroughVersionedPersistence() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        var store = ChatWorkspaceRegistryStore(persistence: harness.persistence)

        let first = try #require(openedWorkspace(store.open(login: "one")))
        let second = try #require(openedWorkspace(store.open(login: "two")))
        let third = try #require(openedWorkspace(store.open(login: "three")))
        #expect(store.move(id: third.id, toIndex: 0))
        #expect(store.select(id: second.id))

        store = ChatWorkspaceRegistryStore(persistence: harness.persistence)

        #expect(store.workspaces.map(\.id) == [third.id, first.id, second.id])
        #expect(store.activeWorkspaceID == second.id)
    }

    @Test
    func invalidOrUnsupportedStoredEnvelopeFallsBackToEmptyRegistry() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }

        harness.defaults.set(Data("not json".utf8), forKey: ChatWorkspaceRegistryPersistence.storageKey)
        var store = ChatWorkspaceRegistryStore(persistence: harness.persistence)
        #expect(store.workspaces.isEmpty)
        #expect(store.activeWorkspaceID == nil)

        let unsupported = """
        {
          "version": 999,
          "snapshot": {
            "workspaces": [],
            "activeWorkspaceID": null
          }
        }
        """
        harness.defaults.set(
            Data(unsupported.utf8),
            forKey: ChatWorkspaceRegistryPersistence.storageKey
        )
        store = ChatWorkspaceRegistryStore(persistence: harness.persistence)

        #expect(store.workspaces.isEmpty)
        #expect(store.activeWorkspaceID == nil)
    }

    @Test
    func persistedSnapshotIsSanitizedWithoutChangingStableWorkspaceIDs() throws {
        let harness = try makeHarness()
        defer { harness.cleanup() }
        let firstID = UUID()
        let duplicateID = UUID()
        harness.persistence.save(
            ChatWorkspaceRegistrySnapshot(
                workspaces: [
                    ChatWorkspace(id: firstID, login: "  MixedCase  "),
                    ChatWorkspace(id: duplicateID, login: "mixedcase"),
                    ChatWorkspace(id: UUID(), login: "   "),
                ],
                activeWorkspaceID: duplicateID
            )
        )

        let store = ChatWorkspaceRegistryStore(persistence: harness.persistence)

        #expect(store.workspaces == [ChatWorkspace(id: firstID, login: "mixedcase")])
        #expect(store.activeWorkspaceID == firstID)
    }

    private func openedWorkspace(
        _ result: ChatWorkspaceRegistryStore.OpenResult
    ) -> ChatWorkspace? {
        guard case let .opened(workspace) = result else {
            return nil
        }
        return workspace
    }

    private func makeHarness() throws -> Harness {
        let suiteName = "ChatWorkspaceRegistryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return Harness(
            suiteName: suiteName,
            defaults: defaults,
            persistence: ChatWorkspaceRegistryPersistence(defaults: defaults)
        )
    }

    private struct Harness {
        let suiteName: String
        let defaults: UserDefaults
        let persistence: ChatWorkspaceRegistryPersistence

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
