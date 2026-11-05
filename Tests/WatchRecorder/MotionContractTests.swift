import Foundation

@main struct MotionContractTests {
    static func main() throws {
        let id = UUID(), run = UUID()
        let data = Data("""
        {"sessionID":"\(id)","sentAt":10,"motionWindow":{"recordingID":"\(run)","start":9,"end":10,"sampleCount":10,"rmsAccelerationG":0.5,"peakAccelerationG":0.8,"meanRotationRadiansPerSecond":1.2,"peakRotationRadiansPerSecond":2}}
        """.utf8)
        let decoded = try JSONDecoder().decode(WatchTelemetry.self, from: data)
        let roundTrip = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
        guard roundTrip["motionWindow"] != nil else {
            print("FAIL: A transported motion window must survive decode and re-encode rather than disappearing.")
            exit(1)
        }
        let legacy = try JSONDecoder().decode(WatchTelemetry.self, from: Data("{\"sessionID\":\"\(id)\",\"sentAt\":0}".utf8))
        let legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        precondition(legacyJSON["motionWindow"] == nil)
        print("Motion telemetry contract: additive motion window and legacy round trip passed")
    }
}
