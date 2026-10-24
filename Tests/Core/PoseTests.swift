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

@Test(arguments: [0.6, 0.7, 0.9])
func measuresPushupBodyLineSeparatelyFromArmDepth(ankleY: Double) {
    var points = Array(repeating: PosePoint(x: 0, y: 0, confidence: 0), count: 33)
    for (index, x, y) in [(11, 0.1, 0.5), (13, 0.1, 0.7), (15, 0.3, 0.7), (23, 0.5, 0.5), (27, 0.9, ankleY)] {
        points[index] = .init(x: x, y: y, confidence: 1)
    }
    let result = PoseGeometry.measure(.init(time: 1, width: 1000, height: 1000, points: points), exercise: .pushup)
    #expect(abs((result?.angle ?? 0) - 90) < 0.01)
    let expected: MovementSample.BodyLine = ankleY == 0.6 ? .steady : (ankleY == 0.7 ? .adjust : .reset)
    #expect(result?.bodyLine == expected)
}
