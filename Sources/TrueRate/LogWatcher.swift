import Foundation

/// Watches Apple Music's unified log output live via `/usr/bin/log stream`
/// and reports the sample rate / bit depth of each track as its audio queue
/// is created. Streaming (rather than polling the log store on a timer) means
/// events arrive within milliseconds of the track starting and none are missed.
final class LogWatcher {

    struct Detection {
        let sampleRate: Int
        let bitDepth: Int?
        let codec: String?
    }

    /// Called on the main queue for every detection.
    var onDetect: ((Detection) -> Void)?
    /// Called on the main queue when the stream starts or stops.
    var onStateChange: ((Bool) -> Void)?

    private(set) var isRunning = false
    private var process: Process?
    private var lineBuffer = Data()
    private var shouldRun = false

    private static let predicate =
        #"process == "Music" AND (eventMessage CONTAINS "Creating AudioQueue with format" OR eventMessage CONTAINS "Input format: ")"#

    // "Creating AudioQueue with format:'qlac', framesPerPacket:4096, sampleRate:44100, ..."
    private static let queueRegex = try! NSRegularExpression(
        pattern: #"Creating AudioQueue with format:'([^']+)'.*?sampleRate:(\d+)"#)
    // "Input format:  2 ch,  44100 Hz, alac (0x00000001) from 16-bit source, ..."
    private static let decoderRegex = try! NSRegularExpression(
        pattern: #"Input format:\s+\d+ ch,\s+(\d+) Hz,\s+(\w+).*?from (\d+)-bit source"#)

    func start() {
        shouldRun = true
        launch()
        primeFromRecentHistory()
    }

    func stop() {
        shouldRun = false
        process?.terminate()
        process = nil
    }

    private func launch() {
        guard shouldRun else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--predicate", Self.predicate, "--style", "ndjson"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                self.onStateChange?(false)
                // The stream can die (e.g. logd restart); revive it.
                if self.shouldRun {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.launch() }
                }
            }
        }

        do {
            try p.run()
            process = p
            isRunning = true
            DispatchQueue.main.async { self.onStateChange?(true) }
        } catch {
            isRunning = false
            DispatchQueue.main.async { self.onStateChange?(false) }
        }
    }

    /// On startup, look a few minutes back so the currently-playing track is
    /// picked up immediately instead of waiting for the next track change.
    private func primeFromRecentHistory() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            p.arguments = [
                "show", "--last", "5m", "--predicate", Self.predicate, "--style", "ndjson",
            ]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return }
            var last: Detection?
            var lastBits: Detection?
            for line in text.split(separator: "\n") {
                guard let message = Self.eventMessage(fromNDJSONLine: String(line)) else {
                    continue
                }
                if let d = Self.parse(message: message) {
                    if d.bitDepth != nil { lastBits = d }
                    last = d
                }
            }
            if let detection = lastBits ?? last {
                DispatchQueue.main.async { self?.onDetect?(detection) }
            }
        }
    }

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let nl = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = lineBuffer[lineBuffer.startIndex..<nl]
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            guard let line = String(data: lineData, encoding: .utf8),
                let message = Self.eventMessage(fromNDJSONLine: line),
                let detection = Self.parse(message: message)
            else { continue }
            DispatchQueue.main.async { self.onDetect?(detection) }
        }
    }

    private static func eventMessage(fromNDJSONLine line: String) -> String? {
        guard line.hasPrefix("{"),
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["eventMessage"] as? String
    }

    static func parse(message: String) -> Detection? {
        let range = NSRange(message.startIndex..., in: message)
        if let m = decoderRegex.firstMatch(in: message, range: range),
            let rateRange = Range(m.range(at: 1), in: message),
            let codecRange = Range(m.range(at: 2), in: message),
            let bitsRange = Range(m.range(at: 3), in: message),
            let rate = Int(message[rateRange]),
            let bits = Int(message[bitsRange])
        {
            return Detection(
                sampleRate: rate, bitDepth: bits, codec: String(message[codecRange]))
        }
        if let m = queueRegex.firstMatch(in: message, range: range),
            let codecRange = Range(m.range(at: 1), in: message),
            let rateRange = Range(m.range(at: 2), in: message),
            let rate = Int(message[rateRange])
        {
            return Detection(
                sampleRate: rate, bitDepth: nil, codec: String(message[codecRange]))
        }
        return nil
    }
}
