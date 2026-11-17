import AVFoundation
import Foundation
import Network
import UIKit

/// Installs a signed IPA on this device via itms-services (OTA), like ESign / Feather:
/// 1. serve the IPA from a tiny HTTP server bound to 127.0.0.1
/// 2. ask a public HTTPS plist generator for the manifest pointing at that local URL
/// 3. open itms-services:// so iOS shows its own "Install" prompt and downloads from us
/// A silent audio loop keeps the server alive while the app is in the background.
final class LocalInstaller {
    static let shared = LocalInstaller()

    /// iOS requires the manifest over HTTPS; the IPA itself may be served over local HTTP.
    static let manifestGenerator = "https://api.palera.in/genPlist"

    enum Event {
        case started
        case downloading
        case finishedServing
        case stopped
    }

    var onEvent: ((Event) -> Void)?

    private let queue = DispatchQueue(label: "dylibsign.installer")
    private var listener: NWListener?
    private var fileURL: URL?
    private var player: AVAudioPlayer?
    private var timeout: DispatchWorkItem?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private static let allowedQuery: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    // MARK: - Public

    /// Starts serving `ipa` and opens the system install prompt.
    @MainActor
    func install(_ result: InjectionResult) async throws {
        stop()
        let port = try await startServer(serving: result.url)
        startKeepAlive()

        let fetchURL = "http://127.0.0.1:\(port)/app.ipa"
        let query = [
            ("bundleid", result.bundleID),
            ("name", result.name),
            ("version", result.version),
            ("fetchurl", fetchURL),
        ]
        .map { "\($0.0)=\(Self.encode($0.1))" }
        .joined(separator: "&")
        let manifest = "\(Self.manifestGenerator)?\(query)"

        guard let itms = URL(string: "itms-services://?action=download-manifest&url=\(Self.encode(manifest))") else {
            stop()
            throw InjectorError("تعذّر إنشاء رابط التثبيت")
        }
        let opened = await UIApplication.shared.open(itms)
        guard opened else {
            stop()
            throw InjectorError("رفض النظام فتح نافذة التثبيت")
        }
        onEvent?(.started)
        scheduleTimeout(seconds: 15 * 60)
    }

    func stop() {
        let wasActive = listener != nil
        timeout?.cancel()
        timeout = nil
        listener?.cancel()
        listener = nil
        fileURL = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.player?.stop()
            self.player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            if self.backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }
            if wasActive { self.onEvent?(.stopped) }
        }
    }

    // MARK: - Server

    private func startServer(serving file: URL) async throws -> UInt16 {
        fileURL = file
        var lastError: Error?
        for _ in 0..<5 {
            let port = UInt16.random(in: 20000...60000)
            do {
                try await listen(on: port)
                return port
            } catch {
                lastError = error
            }
        }
        throw InjectorError("تعذّر تشغيل خادم التثبيت: \(lastError?.localizedDescription ?? "")")
    }

    private func listen(on port: UInt16) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw InjectorError("منفذ غير صالح") }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        let listener = try NWListener(using: parameters)

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receiveRequest(on: connection, buffer: Data())
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = Once()
            listener.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready:
                    once.done = true
                    continuation.resume()
                case .failed(let error):
                    once.done = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    once.done = true
                    continuation.resume(throwing: InjectorError("أُلغي الخادم"))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: buffer[buffer.startIndex..<end.lowerBound], as: UTF8.self)
                self.handle(header: header, on: connection)
            } else if isComplete || error != nil || buffer.count > 64 * 1024 {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func handle(header: String, on connection: NWConnection) {
        let lines = header.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return respond(connection, status: "400 Bad Request") }
        let method = String(parts[0])
        let path = String(parts[1]).components(separatedBy: "?")[0]

        var range: String?
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1)
            if pieces.count == 2, pieces[0].trimmingCharacters(in: .whitespaces).lowercased() == "range" {
                range = pieces[1].trimmingCharacters(in: .whitespaces)
            }
        }

        guard path == "/app.ipa", let file = fileURL,
              let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int else {
            return respond(connection, status: "404 Not Found")
        }

        var start = 0
        var end = size - 1
        var partial = false
        if let range, range.hasPrefix("bytes=") {
            let spec = range.dropFirst(6).split(separator: ",").first ?? ""
            let bounds = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            if bounds.count == 2 {
                if let s = Int(bounds[0]) {
                    start = s
                    if let e = Int(bounds[1]) { end = min(e, size - 1) }
                } else if let suffix = Int(bounds[1]) {
                    start = max(0, size - suffix)
                }
                partial = true
            }
        }
        guard start <= end, start < size else {
            return respond(connection, status: "416 Range Not Satisfiable", extra: "Content-Range: bytes */\(size)\r\n")
        }

        let length = end - start + 1
        var head = "HTTP/1.1 \(partial ? "206 Partial Content" : "200 OK")\r\n"
        head += "Content-Type: application/octet-stream\r\n"
        head += "Content-Length: \(length)\r\n"
        head += "Accept-Ranges: bytes\r\n"
        if partial { head += "Content-Range: bytes \(start)-\(end)/\(size)\r\n" }
        head += "Connection: close\r\n\r\n"

        if method == "HEAD" {
            connection.send(content: Data(head.utf8), isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            return
        }

        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return respond(connection, status: "500 Internal Server Error")
        }
        DispatchQueue.main.async { self.onEvent?(.downloading) }
        scheduleTimeout(seconds: 15 * 60)
        connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else { try? handle.close(); connection.cancel(); return }
            try? handle.seek(toOffset: UInt64(start))
            self?.stream(handle, remaining: length, on: connection, servedWholeFile: start == 0 && length == size)
        })
    }

    private func stream(_ handle: FileHandle, remaining: Int, on connection: NWConnection, servedWholeFile: Bool) {
        if remaining <= 0 {
            try? handle.close()
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
            if servedWholeFile {
                DispatchQueue.main.async { self.onEvent?(.finishedServing) }
                // Give installd time to finish, then shut down.
                scheduleTimeout(seconds: 120)
            }
            return
        }
        let chunk = handle.readData(ofLength: min(256 * 1024, remaining))
        guard !chunk.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error == nil else { try? handle.close(); connection.cancel(); return }
            self?.stream(handle, remaining: remaining - chunk.count, on: connection, servedWholeFile: servedWholeFile)
        })
    }

    private func respond(_ connection: NWConnection, status: String, extra: String = "") {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\n\(extra)Connection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func scheduleTimeout(seconds: Double) {
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        timeout = work
        queue.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Keep alive in background

    @MainActor
    private func startKeepAlive() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "install") { [weak self] in
            guard let self else { return }
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: Self.silentWAV())
            player.numberOfLoops = -1
            player.volume = 0
            player.play()
            self.player = player
        } catch {
            // Without audio the server still works while the app stays in the foreground.
        }
    }

    /// One second of 8 kHz mono 16-bit silence.
    private static func silentWAV() -> Data {
        let sampleRate: UInt32 = 8000
        let dataSize: UInt32 = sampleRate * 2
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataSize)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataSize)
        d.append(Data(count: Int(dataSize)))
        return d
    }

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowedQuery) ?? value
    }
}

private final class Once {
    var done = false
}
