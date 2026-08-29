import Combine
import CoreAudio
import Foundation
import ServiceManagement

struct SwitchEvent: Identifiable {
    let id = UUID()
    let date: Date
    let track: String?
    let sampleRate: Double
    let bitDepth: Int?
    let deviceRate: Double
    let switched: Bool
}

@MainActor
final class SwitchController: ObservableObject {

    // Detected from Apple Music
    @Published var detectedRate: Double?
    @Published var detectedBits: Int?
    @Published var detectedCodec: String?

    // Device state
    @Published var devices: [OutputDevice] = []
    @Published var activeDeviceID: AudioDeviceID?
    @Published var deviceRate: Double?
    @Published var supportedRates: [Double] = []

    // Follows system default output unless the user pins a device.
    @Published var pinnedDeviceUID: AudioDeviceID? {
        didSet { refreshDevices() }
    }

    @Published var autoSwitch: Bool {
        didSet { UserDefaults.standard.set(autoSwitch, forKey: "autoSwitch") }
    }
    @Published var isListening = false
    @Published var history: [SwitchEvent] = []
    @Published var trackName: String?
    @Published var trackArtist: String?
    @Published var launchAtLogin: Bool {
        didSet { updateLoginItem() }
    }

    var isMatched: Bool {
        guard let d = detectedRate, let dev = deviceRate else { return false }
        let target = bestTargetRate(for: d) ?? d
        return abs(target - dev) < 1
    }

    private let logWatcher = LogWatcher()
    private let hardwareObserver = AudioHardwareObserver()

    init() {
        autoSwitch = (UserDefaults.standard.object(forKey: "autoSwitch") as? Bool) ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled

        refreshDevices()

        hardwareObserver.onChange = { [weak self] in self?.refreshDevices() }
        hardwareObserver.start()

        logWatcher.onDetect = { [weak self] detection in
            self?.handle(detection)
        }
        logWatcher.onStateChange = { [weak self] running in
            self?.isListening = running
        }
        logWatcher.start()

        observeTrackInfo()
    }

    // MARK: - Devices

    func refreshDevices() {
        devices = CoreAudioHelper.allOutputDevices()
        let target = pinnedDeviceUID.flatMap { pinned in
            devices.first(where: { $0.id == pinned })?.id
        } ?? CoreAudioHelper.defaultOutputDeviceID()
        activeDeviceID = target
        if let id = target {
            deviceRate = CoreAudioHelper.nominalSampleRate(of: id)
            supportedRates = CoreAudioHelper.availableSampleRates(of: id)
            hardwareObserver.watchSampleRate(of: id)
        } else {
            deviceRate = nil
            supportedRates = []
        }
    }

    var activeDeviceName: String {
        guard let id = activeDeviceID else { return "No output device" }
        return devices.first(where: { $0.id == id })?.name
            ?? CoreAudioHelper.name(of: id) ?? "Unknown device"
    }

    // MARK: - Detection handling

    private func handle(_ detection: LogWatcher.Detection) {
        let rate = Double(detection.sampleRate)
        detectedRate = rate
        if let bits = detection.bitDepth { detectedBits = bits }
        if let codec = detection.codec {
            // New track at a new rate but codec line had no bit depth yet
            if detection.bitDepth == nil && codec != "alac" { detectedBits = nil }
            detectedCodec = codec
        }
        applyIfNeeded(reason: "track")
    }

    /// Sets the device to the best rate for the detected track, if needed.
    func applyIfNeeded(reason: String) {
        guard autoSwitch, let detected = detectedRate, let deviceID = activeDeviceID,
            let current = CoreAudioHelper.nominalSampleRate(of: deviceID),
            let target = bestTargetRate(for: detected)
        else { return }

        guard abs(current - target) > 1 else { return }

        let ok = CoreAudioHelper.setNominalSampleRate(of: deviceID, to: target)
        // Re-read after a moment; some devices take time to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshDevices()
        }
        record(switched: ok, from: current, to: target)
    }

    /// Exact match if the device supports it; otherwise the highest supported
    /// rate in the same family (integer multiple), otherwise the closest rate.
    func bestTargetRate(for detected: Double) -> Double? {
        guard !supportedRates.isEmpty else { return detected }
        if let exact = supportedRates.first(where: { abs($0 - detected) < 1 }) {
            return exact
        }
        let family = supportedRates.filter {
            $0.truncatingRemainder(dividingBy: detected) < 1
                || detected.truncatingRemainder(dividingBy: $0) < 1
        }
        if let best = family.filter({ $0 <= detected }).max() ?? family.min() {
            return best
        }
        return supportedRates.min(by: { abs($0 - detected) < abs($1 - detected) })
    }

    private func record(switched: Bool, from: Double, to: Double) {
        let event = SwitchEvent(
            date: Date(),
            track: trackName,
            sampleRate: detectedRate ?? to,
            bitDepth: detectedBits,
            deviceRate: to,
            switched: switched)
        history.insert(event, at: 0)
        if history.count > 8 { history.removeLast() }
    }

    // MARK: - Track info (no permissions needed)

    private func observeTrackInfo() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil, queue: .main
        ) { [weak self] note in
            let info = note.userInfo
            let name = info?["Name"] as? String
            let artist = info?["Artist"] as? String
            Task { @MainActor in
                self?.trackName = name
                self?.trackArtist = artist
            }
        }
    }

    // MARK: - Login item

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Formatting

    static func format(rate: Double) -> String {
        let khz = rate / 1000
        return khz == khz.rounded()
            ? String(format: "%.0f kHz", khz)
            : String(format: "%.1f kHz", khz)
    }

    static func shortFormat(rate: Double) -> String {
        let khz = rate / 1000
        return khz == khz.rounded()
            ? String(format: "%.0f", khz)
            : String(format: "%.1f", khz)
    }
}
