import Testing
@testable import UnbluMeet

@Test func screenKeyIsDistinctFromTheCameraKey() {
    let identity = "alice"
    #expect(RoomController.screenKey(for: identity) != identity)
}

@Test func screenKeysAreRecognisable() {
    #expect(RoomController.isScreenKey(RoomController.screenKey(for: "alice")))
    #expect(!RoomController.isScreenKey("alice"))
}

@Test func screenKeysStayDistinctBetweenParticipants() {
    #expect(RoomController.screenKey(for: "alice") != RoomController.screenKey(for: "bob"))
}

@Test func shareTiebreakIsDeterministicAndAsymmetric() {
    // Exactly one side yields, whichever order the collision is seen in.
    let aliceYields = RoomController.shouldYieldShare(mine: "alice", theirs: "bob")
    let bobYields = RoomController.shouldYieldShare(mine: "bob", theirs: "alice")
    #expect(aliceYields != bobYields)
}

@Test func shareTiebreakPrefersTheLexicographicallyLargerIdentity() {
    #expect(RoomController.shouldYieldShare(mine: "alice", theirs: "bob"))
    #expect(!RoomController.shouldYieldShare(mine: "bob", theirs: "alice"))
}

@Test func sessionIdentityIsUniquePerJoin() {
    // Two clients sharing one LiveKit identity evict each other, and a stale
    // participant from a crash blocks a rejoin — both look like timeouts.
    let a = RoomController.sessionIdentity(for: "person1")
    let b = RoomController.sessionIdentity(for: "person1")
    #expect(a != b)
}

@Test func sessionIdentityKeepsThePersonIdRecognisable() {
    let identity = RoomController.sessionIdentity(for: "person1")
    #expect(identity.hasPrefix("person1"))
}

@Test func sessionIdentityDoesNotLookLikeAScreenKey() {
    // Screen keys are suffixed #screen; the session suffix must not collide.
    let identity = RoomController.sessionIdentity(for: "person1")
    #expect(!RoomController.isScreenKey(identity))
}
