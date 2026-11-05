import XCTest
import SwiftUI
@testable import Spottr

@MainActor final class MovementArtworkTests: XCTestCase {
    func testHalfSquatGuideUsesTheWorkoutIllustration() throws {
        XCTAssertNotNil(UIImage(named: "squat-mid"), "The workout resource must be bundled.")
        let guide = try render(StickFigureArtwork(exercise: .halfSquat))
        let workout = try render(Image("squat-mid").resizable().scaledToFit())
        XCTAssertEqual(guide.pngData(), workout.pngData(), "The introduction and exercise library should use the established workout figure.")
    }

    func testEveryTrackedMovementHasBundledArtworkAtEachDemonstrationPhase() {
        for exercise in Exercise.allCases {
            for phase in MovementIllustration.Phase.allCases {
                let name = MovementIllustration.assetName(for: exercise, phase: phase)
                XCTAssertNotNil(UIImage(named: name), "Missing illustration for \(exercise.rawValue): \(name)")
            }
        }
    }

    func testSupportedSquatShowsStableSupportBesideTheWorkoutFigure() throws {
        let supported = try render(StickFigureArtwork(exercise: .supportedSquat))
        let capture = XCTAttachment(image: supported); capture.name = "Supported squat guide"; capture.lifetime = .keepAlways; add(capture)
        let unsupported = try render(StickFigureArtwork(exercise: .halfSquat))
        XCTAssertNotEqual(supported.pngData(), unsupported.pngData(), "A supported squat must visibly show the stable support it asks the person to hold.")
    }

    private func render(_ view: some View) throws -> UIImage {
        let renderer = ImageRenderer(content: view.frame(width: 240, height: 240))
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage)
    }
}
