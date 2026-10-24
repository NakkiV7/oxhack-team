import XCTest

final class ReleasePackagingTests: XCTestCase {
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

    private func privacyReasons(in bundle: URL) throws -> [String: Set<String>] {
        let file = bundle.appendingPathComponent("PrivacyInfo.xcprivacy")
        let manifest = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any])
        XCTAssertEqual(Set(manifest.keys), ["NSPrivacyAccessedAPITypes"])
        let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        return try entries.reduce(into: [:]) { result, entry in
            let category = try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String)
            let reasons = try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
            XCTAssertNil(result[category], "Duplicate required API category")
            result[category] = Set(reasons)
        }
    }

    func testHostAppBundlesRequiredPrivacyReasonsWithoutCollectionAttestations() throws {
        XCTAssertEqual(try privacyReasons(in: Bundle.main.bundleURL), [
            "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"]
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
        XCTAssertEqual(try privacyReasons(in: watch), ["NSPrivacyAccessedAPICategorySystemBootTime": ["8FFB.1"]])
    }
}
