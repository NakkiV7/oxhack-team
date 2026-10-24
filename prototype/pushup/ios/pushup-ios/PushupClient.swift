import Foundation
import Network
import Observation
import UIKit

/// Connects to the Mac's `pushup` server and streams live state over Server-Sent Events.
/// Uses a raw TCP connection (HTTP/1.0 GET) rather than URLSession, so App Transport Security
/// (which blocks plain http to a LAN IP) is not involved.
@Observable
final class PushupClient {
    enum Status: Equatable {
        case idle, connecting, connected, failed(String)
    }

    private(set) var state: PushupState?
    /// Latest camera frame from the Mac (small JPEG), drawn under the pose overlay.
    private(set) var frame: UIImage?
    /// Coach messages, oldest first. The server replays its log on every connect.
    private(set) var coach: [CoachMessage] = []
    /// Questions the user asked the coach this session.
    private(set) var chat: [QA] = []
    private(set) var status: Status = .idle

    private var connection: NWConnection?
    private var target: (host: String, port: UInt16)?
    private var buffer = Data()
    private var headerDone = false
    private var lastRx = Date()
    private var watchdog: Timer?

    /// `input` is "192.168.1.5" or "192.168.1.5:3001".
    func connect(to input: String) {
        let parts = input.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard let host = parts.first, !host.isEmpty else { return }
        let port = parts.count > 1 ? UInt16(parts[1]) ?? 3001 : 3001
        target = (String(host), port)
        open()
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAlive() }
        }
    }

    func disconnect() {
        target = nil
        watchdog?.invalidate()
        connection?.cancel()
        connection = nil
        status = .idle
        state = nil
        frame = nil
        coach = []
        chat = []
    }

    private func open() {
        guard let target, let port = NWEndpoint.Port(rawValue: target.port) else { return }
        connection?.cancel()
        buffer = Data()
        headerDone = false
        lastRx = Date()
        status = .connecting

        let conn = NWConnection(host: NWEndpoint.Host(target.host), port: port, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self, weak conn] newState in
            MainActor.assumeIsolated {
                guard let self, let conn, conn === self.connection else { return }
                switch newState {
                case .ready:
                    let request = "GET /events HTTP/1.0\r\nHost: \(target.host)\r\nAccept: text/event-stream\r\n\r\n"
                    conn.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
                    self.receive(on: conn)
                case .failed(let error):
                    self.status = .failed(error.localizedDescription)
                    self.retrySoon()
                case .waiting(let error):
                    self.status = .failed(error.localizedDescription)
                default:
                    break
                }
            }
        }
        conn.start(queue: .main)
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak conn] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self, let conn, conn === self.connection else { return }
                if let data, !data.isEmpty {
                    self.lastRx = Date()
                    self.consume(data)
                }
                if isComplete || error != nil {
                    self.status = .failed("Disconnected")
                    self.retrySoon()
                } else {
                    self.receive(on: conn)
                }
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        if !headerDone {
            guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            headerDone = true
            status = .connected
        }
        let separator = Data("\n\n".utf8)
        while let range = buffer.range(of: separator) {
            let message = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            guard let text = String(data: message, encoding: .utf8) else { continue }
            let isFrame = text.hasPrefix("event: frame")
            let isCoach = text.hasPrefix("event: coach")
            for line in text.split(separator: "\n") where line.hasPrefix("data: ") {
                if isFrame {
                    if let jpeg = Data(base64Encoded: String(line.dropFirst(6))) { frame = UIImage(data: jpeg) }
                    continue
                }
                let json = Data(line.dropFirst(6).utf8)
                if isCoach {
                    if let msg = try? JSONDecoder().decode(CoachMessage.self, from: json),
                       !coach.contains(where: { $0.time == msg.time }) { coach.append(msg) }
                    continue
                }
                if let decoded = try? JSONDecoder().decode(PushupState.self, from: json) {
                    state = decoded
                }
            }
        }
    }

    /// Sends a question (max 256 characters) to the Mac, which answers from official health sources only.
    @MainActor func ask(_ question: String) async {
        let q = String(question.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQuestionLength))
        guard !q.isEmpty else { return }
        var item = QA(question: q)
        chat.append(item)
        let index = chat.count - 1
        func finish(_ answer: String, sources: [Source] = [], failed: Bool = false) {
            guard chat.indices.contains(index), chat[index].id == item.id else { return }
            item.answer = answer; item.sources = sources; item.failed = failed
            chat[index] = item
        }
        guard let target else { return finish("Not connected to the Mac.", failed: true) }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["q": q])
            let data = try await HTTPPost.send(host: target.host, port: target.port, path: "/ask", body: body)
            let response = try JSONDecoder().decode(AskResponse.self, from: data)
            if let answer = response.answer { finish(answer, sources: response.sources ?? []) }
            else { finish(response.error ?? "No answer.", failed: true) }
        } catch {
            finish("Couldn't reach the coach. Check the connection and try again.", failed: true)
        }
    }

    private func retrySoon() {
        connection?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.target != nil else { return }
                if case .connected = self.status { return }
                self.open()
            }
        }
    }

    /// The server pings every 3 s; no bytes for 8 s means the Wi-Fi or the Mac went away.
    private func checkAlive() {
        guard target != nil, case .connected = status else { return }
        if Date().timeIntervalSince(lastRx) > 8 {
            status = .failed("Lost connection")
            open()
        }
    }
}
