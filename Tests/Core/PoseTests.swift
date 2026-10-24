import Testing
@testable import SpottrCore

@Test func measuresAnglesInImageSpaceRatherThanStretchedNormalizedSpace() {
    var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
    points[11] = .init(x: 0.1, y: 0.1, confidence: 1)
    points[23] = .init(x: 0, y: 0.5, confidence: 1)
    points[25] = .init(x: 0.5, y: 0.5, confidence: 1)
    points[27] = .init(x: 0.75, y: 0, confidence: 1)
    let frame = PoseFrame(time: 1, width: 1000, height: 500, points: points)
    let result = PoseGeometry.measure(frame, exercise: .squat)
    #expect(abs((result?.angle ?? 0) - 135) < 0.01)
    points[25] = .init(x: 0.5, y: 0.5, confidence: 0.2)
    #expect(PoseGeometry.measure(.init(time: 2, width: 1000, height: 500, points: points), exercise: .squat) == nil)
}
