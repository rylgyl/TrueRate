import CoreAudio
import Foundation

struct OutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

enum CoreAudioHelper {

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var devID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID)
        guard err == noErr, devID != kAudioObjectUnknown else { return nil }
        return devID
    }

    static func allOutputDevices() -> [OutputDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
            size > 0
        else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap { id in
            guard outputChannelCount(of: id) > 0 else { return nil }
            return OutputDevice(id: id, name: name(of: id) ?? "Device \(id)")
        }
    }

    static func name(of deviceID: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var cfName: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let err = withUnsafeMutablePointer(to: &cfName) { ptr in
            AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, ptr)
        }
        guard err == noErr else { return nil }
        return cfName as String
    }

    static func outputChannelCount(of deviceID: AudioDeviceID) -> Int {
        var addr = address(
            kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr,
            size > 0
        else { return 0 }
        let bufferListPtr = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListPtr.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, bufferListPtr) == noErr
        else { return 0 }
        let bufferList = bufferListPtr.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func nominalSampleRate(of deviceID: AudioDeviceID) -> Double? {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &rate) == noErr,
            rate > 0
        else { return nil }
        return rate
    }

    @discardableResult
    static func setNominalSampleRate(of deviceID: AudioDeviceID, to rate: Double) -> Bool {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var value: Float64 = rate
        let size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectSetPropertyData(deviceID, &addr, 0, nil, size, &value) == noErr
    }

    static func availableSampleRates(of deviceID: AudioDeviceID) -> [Double] {
        var addr = address(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr,
            size > 0
        else { return [] }
        let count = Int(size) / MemoryLayout<AudioValueRange>.size
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: count)
        guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &ranges) == noErr
        else { return [] }

        let common: [Double] = [
            44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000,
        ]
        var rates = Set<Double>()
        for range in ranges {
            if range.mMinimum == range.mMaximum {
                rates.insert(range.mMinimum)
            } else {
                for r in common where r >= range.mMinimum && r <= range.mMaximum {
                    rates.insert(r)
                }
            }
        }
        return rates.sorted()
    }
}

/// Observes CoreAudio hardware: default output device changes, device list
/// changes, and the active device's nominal sample rate.
final class AudioHardwareObserver {
    var onChange: (() -> Void)?

    private var listeningDeviceID: AudioDeviceID?
    private let queue = DispatchQueue.main
    private lazy var listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.onChange?()
    }

    func start() {
        var defaultAddr = CoreAudioHelper.address(kAudioHardwarePropertyDefaultOutputDevice)
        var devicesAddr = CoreAudioHelper.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddr, queue, listenerBlock)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &devicesAddr, queue, listenerBlock)
    }

    func watchSampleRate(of deviceID: AudioDeviceID) {
        guard deviceID != listeningDeviceID else { return }
        var rateAddr = CoreAudioHelper.address(kAudioDevicePropertyNominalSampleRate)
        if let old = listeningDeviceID {
            AudioObjectRemovePropertyListenerBlock(old, &rateAddr, queue, listenerBlock)
        }
        AudioObjectAddPropertyListenerBlock(deviceID, &rateAddr, queue, listenerBlock)
        listeningDeviceID = deviceID
    }
}
