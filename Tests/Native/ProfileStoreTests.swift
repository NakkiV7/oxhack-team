import Foundation
import Testing
@testable import SpottrCore

@Test @MainActor func introductionShowsForRealFirstRunAndOnlyBypassesValidTestNamespaces() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = NativeProfileStore(url: folder.appendingPathComponent("profile.json"))
    #expect(store.shouldShowIntroduction(environment: [:]))
    #expect(store.shouldShowIntroduction(environment: ["SPOTTR_DATA_NAMESPACE": "invalid"]))
    let namespace = ["SPOTTR_DATA_NAMESPACE": UUID().uuidString]
    #expect(!store.shouldShowIntroduction(environment: namespace))
    #expect(store.shouldShowIntroduction(environment: namespace.merging(["SPOTTR_FORCE_ONBOARDING": "1"], uniquingKeysWith: { _, new in new })))
    try store.save(LocalProfile())
    #expect(!store.shouldShowIntroduction(environment: [:]))
    #expect(store.shouldShowIntroduction(environment: ["SPOTTR_FORCE_ONBOARDING": "1"]))
}

@Test @MainActor func localProfilePersistsOnlyAfterExplicitSaveAndResetLeavesHistoryUntouched() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let historyURL = folder.appendingPathComponent("history.json")
    let original = Data("existing history must survive".utf8)
    try original.write(to: historyURL)
    let url = folder.appendingPathComponent("profile.json")
    let store = NativeProfileStore(url: url)
    #expect(store.profile == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    let profile = try LocalProfile(name: "Omar", weeklyTarget: 3, goals: [.strength])
    try store.save(profile)
    #expect(NativeProfileStore(url: url).profile == profile)
    try store.resetProfile()
    #expect(store.profile == nil)
    #expect(NativeProfileStore(url: url).profile == nil)
    #expect(try Data(contentsOf: historyURL) == original)
}

@Test @MainActor func unreadableProfileIsReportedAndPreservedUntilAnExplicitSave() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("profile.json"), original = Data("invalid saved profile".utf8)
    try original.write(to: url)
    let store = NativeProfileStore(url: url)
    #expect(store.profile == nil)
    #expect(store.loadError != nil)
    #expect(try Data(contentsOf: url) == original)
    let profile = try LocalProfile(weeklyTarget: 2, goals: [.mobility])
    try store.save(profile)
    #expect(store.profile == profile)
    #expect(store.loadError == nil)
}

@Test @MainActor func failedProfileWriteDoesNotClaimAProfileWasSaved() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let blocker = folder.appendingPathComponent("not-a-directory")
    let original = Data("preserve this file".utf8)
    try original.write(to: blocker)
    let store = NativeProfileStore(url: blocker.appendingPathComponent("profile.json"))
    #expect(throws: Error.self) { try store.save(LocalProfile()) }
    #expect(store.profile == nil)
    #expect(try Data(contentsOf: blocker) == original)
}
