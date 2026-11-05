import XCTest
import HealthKit
@testable import Spottr

@MainActor
final class HealthQuantityConversionTests: XCTestCase {
    func testOxygenFractionBecomesDisplayedPercentWithOriginalDateAndSource() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let value = try XCTUnwrap(AppleHealthReadingClient.observation(
            metric: .oxygenSaturation, quantity: HKQuantity(unit: .percent(), doubleValue: 0.98),
            date: date, source: "Watch"))
        XCTAssertEqual(value.value, 98, accuracy: 0.000_001)
        XCTAssertEqual(value.unit, "%")
        XCTAssertEqual(value.date, date)
        XCTAssertEqual(value.source, "Watch")
    }

    func testOneMinuteRecoveryUsesCountQuantityAndDisplaysHeartRateDrop() throws {
        let value = try XCTUnwrap(AppleHealthReadingClient.observation(
            metric: .heartRateRecoveryOneMinute, quantity: HKQuantity(unit: .count(), doubleValue: 18),
            date: Date(timeIntervalSince1970: 1_800_000_000), source: "Watch"))
        XCTAssertEqual(value.value, 18)
        XCTAssertEqual(value.unit, "bpm")
        XCTAssertEqual(value.metric, .heartRateRecoveryOneMinute)
    }

    func testCardioFitnessComposedQuantityRetainsMillilitresPerKilogramPerMinute() throws {
        let unit = HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())
        let value = try XCTUnwrap(AppleHealthReadingClient.observation(
            metric: .vo2Max, quantity: HKQuantity(unit: unit, doubleValue: 40),
            date: Date(timeIntervalSince1970: 1_800_000_000), source: "Watch"))
        XCTAssertEqual(value.value, 40, accuracy: 0.000_001)
        XCTAssertEqual(value.unit, "mL/kg/min")
    }

    func testIncompatibleQuantityIsOmittedBeforeHealthKitCanRaiseAnException() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNil(AppleHealthReadingClient.observation(metric: .restingHeartRate,
            quantity: HKQuantity(unit: .meter(), doubleValue: 2), date: date, source: "Watch"))
        XCTAssertNil(AppleHealthReadingClient.observation(metric: .heartRateRecoveryOneMinute,
            quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 18), date: date, source: "Watch"))
    }
}
