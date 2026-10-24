import Foundation

public enum SecondaryCameraError: Error, Equatable, LocalizedError {
    case configuration, invalidResponse, staleFrame, rejected(Int)
    public var errorDescription: String? {
        switch self {
        case .configuration: return "Add an HTTPS Pi address, its certificate SHA256 pin and its access token in Pi camera settings."
        case .invalidResponse: return "The Pi camera returned an invalid response. Check its connection and restart capture."
        case .staleFrame: return "The Pi camera frame expired. Check its connection and restart capture."
        case .rejected(let code):
            return code == 401 ? "Pi camera access was refused. Check its access token." : "The Pi camera is unavailable (\(code)). Check its connection and restart capture."
        }
    }
}

public struct SecondaryCameraFrameMetadata: Equatable, Sendable {
    public let frameID: String
    public let sequence: Int64
    public let capturedAt: Date
    public let validFor: TimeInterval
    public init(frameID: String, capturedAt: String, serverAgeMilliseconds: String,
                expectedCaptureID: String, receivedAt: Date, requestDuration: TimeInterval,
                afterSequence: Int64?) throws {
        let parts = frameID.split(separator: ":", omittingEmptySubsequences: false)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard parts.count == 2, let sequence = Int64(parts[1]),
              let captured = formatter.date(from: capturedAt), let age = Double(serverAgeMilliseconds) else {
            throw SecondaryCameraError.invalidResponse
        }
        let wallAge = receivedAt.timeIntervalSince(captured)
        guard parts[0] == expectedCaptureID, sequence > 0, sequence >= (afterSequence ?? 0),
              age.isFinite, age >= 0, requestDuration.isFinite, requestDuration >= 0,
              wallAge >= -2, wallAge < 2, age / 1000 + requestDuration < 2 else {
            throw SecondaryCameraError.staleFrame
        }
        self.frameID = frameID; self.sequence = sequence; self.capturedAt = captured
        self.validFor = min(2 - age / 1000 - requestDuration, 2 - max(0, wallAge))
    }
}

public struct SecondaryCameraConfig: Equatable, Sendable {
    public let baseURL: URL
    public let certificateSHA256: String
    public static func validateAccessToken(_ token: String) throws {
        guard !token.isEmpty, token.utf8.count <= 1024,
              token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw SecondaryCameraError.configuration }
    }
    public init(url: String, certificateSHA256: String) throws {
        let address = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = certificateSHA256.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ":", with: "").lowercased()
        guard let components = URLComponents(string: address), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil, ["", "/"].contains(components.path),
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let parsed = components.url, pin.count == 64,
              pin.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw SecondaryCameraError.configuration }
        self.baseURL = parsed
        self.certificateSHA256 = pin
    }
}
