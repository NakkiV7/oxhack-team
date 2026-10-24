import XCTest
import Security
import CryptoKit
@testable import Spottr

final class SecondaryCameraTrustTests: XCTestCase {
    func testPinStillRequiresTheConfiguredHostAndCertificateValidityDates() throws {
        let data = try XCTUnwrap(Data(base64Encoded: "MIIDQjCCAiqgAwIBAgIUJBiT5EL32QNkPmx06P+TTQDHkeYwDQYJKoZIhvcNAQELBQAwGTEXMBUGA1UEAwwOc3BvdHRyLWZpeHR1cmUwHhcNMjYxMDI0MTkwNDA1WhcNMjYxMDI1MTkwNDA1WjAZMRcwFQYDVQQDDA5zcG90dHItZml4dHVyZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAK2ArisE2OWkGOrLEMqiLKjHcXNuD7pEI870ocpdDpSXihtX0x7e6A2D/UHC7Mob1a3dunRxvkQc2fP20PdpzxD8DlJo6EN6rFVLC5UOWZlh41pPlENXYkjbPeo9Yh6wlgyHQJ6pw/EVJ5s0e6VsnPligncGiY+Z8ZS0v6xBPQSZUw7EZ0kNzHaqug+LrV+kyQhtmyAqipgoIKW78HfFwYoz/8bQ6otrxzmyYyZfbqVBk3afkKBVEShX2GDHZEgU6fTjp2Ih0L4mZFfPfRHON7he5HvtwBUzNr8BqeED3u832X8TBdafQjCo2WCwUTRaQTanpNsf9db+n6ln044xyOkCAwEAAaOBgTB/MB0GA1UdDgQWBBQKicwPHtIyAejsdpIM8+ibHN8aoTAfBgNVHSMEGDAWgBQKicwPHtIyAejsdpIM8+ibHN8aoTAPBgNVHRMBAf8EBTADAQH/MBcGA1UdEQQQMA6CDGNhbWVyYS5sb2NhbDATBgNVHSUEDDAKBggrBgEFBQcDATANBgkqhkiG9w0BAQsFAAOCAQEAD7DKKBm1uNTqoc3oiPiEXO2d6nboRiEJ/ZQoa4aln679CHIwCzhQ13sj+DRjxRXJ/qPQxVD/T5W+YUrFoCaI/MkjS3UYOufRQokWG2ZLwMB5UgiPx8RhhAlCVwmCZQuc3BciO8LLlRA9AveK927nd+qe21MZEAXISbnoKhIT4zUNZirJJhWcNfmqBMlac+uPGC0hYp+FrpzGWanB0H5XEc5ErSJ47eqTqx80ysTYuoG+7U9f5fvEbUTLMO8oheozy+WE76zTFNnFPFTl3lxh7IBRQpEPQZaaIg+K4vTxzP0eFFhV5bcjWuU0IwuQq//FLum15KoNxWMHkS4PIjzcLA=="))
        let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, data as CFData))
        let pin = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let issued = Date(timeIntervalSince1970: 1792868645.8851788)
        let cases: [(String, String, String, Date, Bool)] = [
            ("camera.local", "camera.local", pin, issued.addingTimeInterval(60), true),
            ("camera.local", "camera.local", String(repeating: "b", count: 64), issued.addingTimeInterval(60), false),
            ("different.local", "different.local", pin, issued.addingTimeInterval(60), false),
            ("camera.local", "different.local", pin, issued.addingTimeInterval(60), false),
            ("camera.local", "camera.local", pin, issued.addingTimeInterval(-3600), false),
            ("camera.local", "camera.local", pin, issued.addingTimeInterval(172800), false),
        ]
        for (configuredHost, challengeHost, fingerprint, date, expected) in cases {
            let configuration = try SecondaryCameraConfig(url: "https://\(configuredHost):8765", certificateSHA256: fingerprint)
            var trust: SecTrust?
            XCTAssertEqual(SecTrustCreateWithCertificates(certificate, SecPolicyCreateSSL(true, challengeHost as CFString), &trust), errSecSuccess)
            XCTAssertEqual(SecondaryCameraTrust.accepts(try XCTUnwrap(trust), host: challengeHost, configuration: configuration, now: date), expected,
                           "Unexpected trust result for \(configuredHost) at \(date)")
        }
    }
    func testRedirectPolicyNeverForwardsTheBearerRequest() throws {
        let configuration = try SecondaryCameraConfig(url: "https://camera.local:8765", certificateSHA256: String(repeating: "a", count: 64))
        let delegate = SecondaryCameraSessionDelegate(configuration: configuration)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://camera.local:8765/frame.jpg")!
        let task = session.dataTask(with: original)
        var redirected = URLRequest(url: URL(string: "https://another.local/frame.jpg")!)
        redirected.setValue("Bearer fixture", forHTTPHeaderField: "Authorization")
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil, headerFields: ["Location": redirected.url!.absoluteString])!
        let invoked = expectation(description: "Redirect refused")
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) { allowed in
            XCTAssertNil(allowed); invoked.fulfill()
        }
        wait(for: [invoked], timeout: 1)
    }

}
