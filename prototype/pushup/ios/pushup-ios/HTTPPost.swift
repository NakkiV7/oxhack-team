import Foundation
import Network

/// Minimal HTTP/1.0 POST over a raw TCP connection (like the SSE client, this avoids App Transport Security
/// blocking plain http to a LAN IP). The server closes the connection after the reply, which ends the body.
enum HTTPPost {
    struct Failure: Error {}

    static func send(host: String, port: UInt16, path: String, body: Data, timeout: TimeInterval = 45) async throws -> Data {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw Failure() }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let queue = DispatchQueue(label: "http-post")

        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            var received = Data()
            func finish(_ result: Result<Data, Error>) {
                guard !finished else { return }
                finished = true
                conn.cancel()
                continuation.resume(with: result)
            }
            func read() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let data { received.append(data) }
                    if error != nil || isComplete {
                        guard let split = received.range(of: Data("\r\n\r\n".utf8)) else { return finish(.failure(Failure())) }
                        finish(.success(received.subdata(in: split.upperBound..<received.endIndex)))
                    } else {
                        read()
                    }
                }
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var request = Data("POST \(path) HTTP/1.0\r\nHost: \(host)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
                    request.append(body)
                    conn.send(content: request, completion: .contentProcessed { error in
                        if error != nil { finish(.failure(Failure())) } else { read() }
                    })
                case .failed, .cancelled:
                    finish(.failure(Failure()))
                default:
                    break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(Failure())) }
        }
    }
}
