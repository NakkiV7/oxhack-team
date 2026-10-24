import Foundation
import Security
import CryptoKit

enum SecondaryCameraTrust {
    static func accepts(_ trust: SecTrust, host: String, configuration: SecondaryCameraConfig, now: Date = Date()) -> Bool {
        guard host.lowercased() == configuration.baseURL.host?.lowercased(),
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = certificates.first else { return false }
        let data = SecCertificateCopyData(leaf) as Data
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == configuration.certificateSHA256,
              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, [leaf] as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetVerifyDate(trust, now as CFDate) == errSecSuccess else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }
}

final class SecondaryCameraSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let configuration: SecondaryCameraConfig
    init(configuration: SecondaryCameraConfig) { self.configuration = configuration }
    static func session(configuration: SecondaryCameraConfig) -> URLSession {
        let options = URLSessionConfiguration.ephemeral
        options.urlCache = nil; options.httpCookieStorage = nil; options.urlCredentialStorage = nil
        options.httpShouldSetCookies = false; options.requestCachePolicy = .reloadIgnoringLocalCacheData
        options.timeoutIntervalForRequest = 2; options.timeoutIntervalForResource = 5
        return URLSession(configuration: options, delegate: SecondaryCameraSessionDelegate(configuration: configuration), delegateQueue: nil)
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.port == (configuration.baseURL.port ?? 443),
              let trust = challenge.protectionSpace.serverTrust,
              SecondaryCameraTrust.accepts(trust, host: challenge.protectionSpace.host, configuration: configuration) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
