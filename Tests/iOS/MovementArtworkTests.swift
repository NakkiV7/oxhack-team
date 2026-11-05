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
        for exercise in Exercise.allCases where !MovementIllustration.usesVector(exercise) {
            for phase in MovementIllustration.Phase.allCases {
                let name = MovementIllustration.assetName(for: exercise, phase: phase)
                XCTAssertNotNil(UIImage(named: name), "Missing illustration for \(exercise.rawValue): \(name)")
            }
        }
    }

    func testSemanticFamiliesRenderDistinctFacelessMovementPhases() throws {
        var images = Set<Data>()
        for exercise in [Exercise.gluteBridge, .seatedKneeExtension, .frontArmRaise, .lateralArmRaise, .standingBicepsCurl, .birdDog, .deadBug, .stepJack] {
            let start = try render(StickFigureArtwork(exercise: exercise, phase: .standing))
            let end = try render(StickFigureArtwork(exercise: exercise, phase: .lowered))
            XCTAssertNotEqual(start.pngData(), end.pngData(), exercise.rawValue)
            images.insert(try XCTUnwrap(end.pngData()))
            let attachment = XCTAttachment(image: end); attachment.name = exercise.rawValue; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(images.count, 8)
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

extension MovementArtworkTests {
    func testRenderedNewMovementReviewBoard() throws {
        let groups: [[Exercise]] = [[.gluteBridge,.seatedKneeExtension,.frontArmRaise],[.standingBicepsCurl,.plank,.sidePlank],[.wallSlide,.kneePlank,.singleLegBalance]]
        let board = VStack(spacing: 18) {
            ForEach(groups.indices, id: \.self) { row in
                HStack(spacing: 18) {
                    ForEach(groups[row], id: \.self) { exercise in
                        VStack(spacing: 8) {
                            Text(exercise.title).font(.system(size: 19, weight: .semibold)).foregroundStyle(.black)
                            HStack(spacing: 6) {
                                StickFigureArtwork(exercise: exercise, phase: .standing).frame(width: 165,height: 180)
                                StickFigureArtwork(exercise: exercise, phase: .lowered).frame(width: 165,height: 180)
                            }
                            Text(exercise.isTimed ? "Selected hold posture" : "Start • range").font(.system(size: 13)).foregroundStyle(.gray)
                        }.frame(width: 350,height: 245)
                    }
                }
            }
        }.padding(20).background(.white)
        let renderer = ImageRenderer(content: board); renderer.scale = 1
        let image = try XCTUnwrap(renderer.uiImage)
        let attachment = XCTAttachment(image: image); attachment.name = "task3-movement-review-board"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
