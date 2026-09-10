import Testing
@testable import UnbluMeet

@Test func theDefaultAliasIsLabelledAndPromotedToTheTop() {
    // The module lists an entry with id "default" whose name is whichever
    // device is currently the system default — so it looked like a duplicate.
    let entries = AudioDevices.entries(from: [
        (id: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone"),
        (id: "default", name: "MacBook Pro Microphone"),
    ])
    #expect(entries.count == 2)
    #expect(entries[0].id == "default")
    #expect(entries[0].label == "System default (MacBook Pro Microphone)")
    #expect(entries[1].label == "MacBook Pro Microphone")
}

@Test func repeatedIdsAreCollapsed() {
    let entries = AudioDevices.entries(from: [
        (id: "a", name: "Immersed"),
        (id: "a", name: "Immersed"),
        (id: "a", name: "Immersed"),
    ])
    #expect(entries.count == 1)
}

@Test func distinctDevicesSharingANameStayDistinguishable() {
    // Two identical USB headsets are not duplicates and must remain selectable.
    let entries = AudioDevices.entries(from: [
        (id: "usb-1", name: "Jabra Evolve"),
        (id: "usb-2", name: "Jabra Evolve"),
    ])
    #expect(entries.map(\.label) == ["Jabra Evolve", "Jabra Evolve (2)"])
    #expect(Set(entries.map(\.id)).count == 2)
}

@Test func anUnnamedDefaultStillReads() {
    let entries = AudioDevices.entries(from: [(id: "default", name: "")])
    #expect(entries[0].label == "System default")
}

@Test func selectionFallsBackToTheDeviceActuallyInUse() {
    let entries = AudioDevices.entries(from: [
        (id: "default", name: "Speakers"),
        (id: "dell", name: "DELL U4025QW"),
    ])
    // Blank selection — what join() used to store — resolves to the live device.
    #expect(AudioDevices.resolvedSelection(current: "", activeID: "dell", entries: entries) == "dell")
}

@Test func anExplicitChoiceIsKeptWhileItExists() {
    let entries = AudioDevices.entries(from: [
        (id: "default", name: "Speakers"),
        (id: "dell", name: "DELL U4025QW"),
    ])
    #expect(AudioDevices.resolvedSelection(current: "dell", activeID: "default", entries: entries) == "dell")
}

@Test func aDisconnectedChoiceFallsBackRatherThanRenderingBlank() {
    // A picker whose selection is not in its own list shows nothing at all.
    let entries = AudioDevices.entries(from: [(id: "default", name: "Speakers")])
    #expect(AudioDevices.resolvedSelection(current: "unplugged-usb", activeID: "", entries: entries) == "default")
}

@Test func anEmptyListResolvesToNothingRatherThanCrashing() {
    #expect(AudioDevices.resolvedSelection(current: "x", activeID: "y", entries: []) == "")
}
