import XCTest

final class ReleasePackagingTests: XCTestCase {
    func testGuardianAuthenticationHasFaceIDPurposeInBuiltHost() throws {
        let purpose = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String)
        XCTAssertTrue(purpose.contains("guardian"))
        XCTAssertFalse(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testRetiredSideCameraPairingIsNotShippedWithTheApp() {
        XCTAssertNil(Bundle.main.url(forResource: "SpottrDemoCamera", withExtension: "json"))
        let purpose = Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String
        XCTAssertEqual(purpose, "Spottr connects to your local workout gateway.")
    }
    func testHealthEnabledHostDeclaresReadAndWorkoutSavePurposes() throws {
        for key in ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"] {
            let purpose = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: key) as? String)
            XCTAssertFalse(purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
    func testHostAndWatchDeclareAuditedExemptEncryption() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool, false)
        let watch = Bundle.main.bundleURL.appendingPathComponent("Watch/SpottrWatch.app/Info.plist")
        let info = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: watch), format: nil) as? [String: Any])
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)
    }

    func testInstallableHostAndWatchHaveMatchingReleaseAndBuildVersions() throws {
        let release = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let build = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        XCTAssertNotNil(release.range(of: #"^\d+(\.\d+){0,2}$"#, options: .regularExpression))
        XCTAssertNotNil(build.range(of: #"^\d+(\.\d+){0,2}$"#, options: .regularExpression))
        let watch = Bundle.main.bundleURL.appendingPathComponent("Watch/SpottrWatch.app/Info.plist")
        let info = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: watch), format: nil) as? [String: Any])
        XCTAssertEqual(info["CFBundleShortVersionString"] as? String, release)
        XCTAssertEqual(info["CFBundleVersion"] as? String, build)
        XCTAssertEqual(info["WKApplication"] as? Bool, true)
    }

    private func privacyManifest(in bundle: URL) throws -> [String: Any] {
        let file = bundle.appendingPathComponent("PrivacyInfo.xcprivacy")
        return try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any])
    }

    private func privacyReasons(in manifest: [String: Any]) throws -> [String: Set<String>] {
        let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        return try entries.reduce(into: [:]) { result, entry in
            XCTAssertEqual(Set(entry.keys), ["NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"])
            let category = try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String)
            let reasons = try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
            XCTAssertNil(result[category], "Duplicate required API category")
            XCTAssertEqual(reasons.count, Set(reasons).count, "Duplicate required API reason")
            result[category] = Set(reasons)
        }
    }

    func testHostAppBundlesRequiredPrivacyReasonsAndDeclaredCollection() throws {
        let manifest = try privacyManifest(in: Bundle.main.bundleURL)
        XCTAssertEqual(Set(manifest.keys), ["NSPrivacyAccessedAPITypes", "NSPrivacyTracking", "NSPrivacyCollectedDataTypes"])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(try privacyReasons(in: manifest), [
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"]
        ])
        let entries = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let purposes: [String: Set<String>] = try entries.reduce(into: [:]) { result, entry in
            XCTAssertEqual(Set(entry.keys), ["NSPrivacyCollectedDataType", "NSPrivacyCollectedDataTypeLinked", "NSPrivacyCollectedDataTypeTracking", "NSPrivacyCollectedDataTypePurposes"])
            let type = try XCTUnwrap(entry["NSPrivacyCollectedDataType"] as? String)
            let values = try XCTUnwrap(entry["NSPrivacyCollectedDataTypePurposes"] as? [String])
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool, true, type)
            XCTAssertEqual(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool, false, type)
            XCTAssertNil(result[type], "Duplicate collected data type")
            XCTAssertEqual(values.count, Set(values).count, "Duplicate collection purpose")
            result[type] = Set(values)
        }
        XCTAssertEqual(purposes, [
            "NSPrivacyCollectedDataTypeEmailAddress": ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
            "NSPrivacyCollectedDataTypeUserID": ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
            "NSPrivacyCollectedDataTypeDeviceID": ["NSPrivacyCollectedDataTypePurposeAppFunctionality", "NSPrivacyCollectedDataTypePurposeAnalytics"],
            "NSPrivacyCollectedDataTypeFitness": ["NSPrivacyCollectedDataTypePurposeAppFunctionality", "NSPrivacyCollectedDataTypePurposeProductPersonalization", "NSPrivacyCollectedDataTypePurposeAnalytics"],
            "NSPrivacyCollectedDataTypeProductInteraction": ["NSPrivacyCollectedDataTypePurposeAnalytics"],
            "NSPrivacyCollectedDataTypeCustomerSupport": ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
        ])
    }

    func testHostHasAppleSDKMetadataAndCorrectApplicationIdentity() throws {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.omarchoudhry.spottr")
        let platform = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "DTPlatformName") as? String)
        XCTAssertTrue(["iphoneos", "iphonesimulator"].contains(platform))
        let sdk = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "DTSDKName") as? String)
        XCTAssertTrue(sdk.hasPrefix(platform))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundlePackageType") as? String, "APPL")
    }

    func testEmbeddedWatchBundlesItsOwnPrivacyReasonsAndMatchingCompanionWhenPresent() throws {
        let watch = Bundle.main.bundleURL.appendingPathComponent("Watch/SpottrWatch.app")
        guard FileManager.default.fileExists(atPath: watch.path) else { throw XCTSkip("This host build does not embed the Watch companion.") }
        let info = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: watch.appendingPathComponent("Info.plist")), format: nil) as? [String: Any])
        XCTAssertEqual(info["CFBundleIdentifier"] as? String, "com.omarchoudhry.spottr.watchkitapp")
        XCTAssertEqual(info["WKCompanionAppBundleIdentifier"] as? String, Bundle.main.bundleIdentifier)
        let manifest = try privacyManifest(in: watch)
        XCTAssertEqual(Set(manifest.keys), ["NSPrivacyAccessedAPITypes"])
        XCTAssertEqual(try privacyReasons(in: manifest), ["NSPrivacyAccessedAPICategorySystemBootTime": ["8FFB.1"]])
    }
}
