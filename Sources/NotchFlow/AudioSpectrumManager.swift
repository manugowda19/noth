import Combine
import CoreAudio
import Foundation

// Real audio-reactive bars: a Core Audio process tap (macOS 14.2+, public API)
// on all system output, read through a private aggregate device, FFT'd into a
// few band levels by `Spectrum`. Opt-in (`AppSettings.showVisualizer`); the
// first start asks for "System Audio Recording" permission. Runs only while
// something is playing, so idle costs nothing. Audio is analyzed in memory and
// never stored.
// ponytail: whole-system tap; per-app taps (only the playing app) if mixing in
// notification sounds ever looks wrong.
final class AudioSpectrumManager: ObservableObject {
    static let shared = AudioSpectrumManager()
    static let bandCount = 7

    /// 0…1 per band, smoothed; nil while not capturing (bars fall back to the
    /// decorative animation).
    @Published private(set) var levels: [Float]?

    private let queue = DispatchQueue(label: "notchflow.spectrum", qos: .userInteractive)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var sampleRate = 48_000.0
    // Audio-queue state: rolling sample window + smoothed levels + throttle.
    private var window = [Float]()
    private var smoothed = [Float](repeating: 0, count: bandCount)
    private var lastPublish = 0.0
    private var sub: AnyCancellable?

    private init() {
        sub = NowPlayingManager.shared.$nowPlaying.map { $0?.playing == true }
            .combineLatest(AppSettings.shared.$showVisualizer)
            .map { $0 && $1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in on ? self?.start() : self?.stop() }
    }

    private func start() {
        guard procID == nil else { return }
        guard #available(macOS 14.2, *), createTap() else { teardown(); return }
    }

    private func stop() {
        teardown()
        levels = nil
    }

    @available(macOS 14.2, *)
    private func createTap() -> Bool {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return false }

        var fmt = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &fmt) == noErr, fmt.mSampleRate > 0 {
            sampleRate = fmt.mSampleRate
        }
        guard let outputUID = Self.defaultOutputUID() else { return false }

        // Private aggregate = the default output (clock source) + our tap.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NØTH Visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr
        else { return false }

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) {
            [weak self] _, input, _, _, _ in self?.consume(input)
        }
        guard status == noErr, let procID else { return false }
        return AudioDeviceStart(aggregateID, procID) == noErr
    }

    private func teardown() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        queue.async { [weak self] in
            self?.window.removeAll()
            self?.smoothed = [Float](repeating: 0, count: Self.bandCount)
        }
    }

    /// Audio queue: append the first channel of the tap's (interleaved float)
    /// buffer to a rolling window, and ~30×/s turn it into smoothed levels.
    private func consume(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let buffer = buffers.first, let data = buffer.mData else { return }
        let channels = max(1, Int(buffer.mNumberChannels))
        let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
        let samples = data.assumingMemoryBound(to: Float.self)
        for f in 0..<frames { window.append(samples[f * channels]) }
        if window.count > Spectrum.fftSize { window.removeFirst(window.count - Spectrum.fftSize) }

        let now = CFAbsoluteTimeGetCurrent()
        guard window.count == Spectrum.fftSize, now - lastPublish > 1.0 / 30 else { return }
        lastPublish = now
        let fresh = Spectrum.levels(window, sampleRate: sampleRate, bands: Self.bandCount)
        // Fast attack, slow release — reads as a meter instead of flicker.
        smoothed = zip(fresh, smoothed).map { new, old in max(new, old * 0.82) }
        let out = smoothed
        DispatchQueue.main.async { [weak self] in
            guard self?.procID != nil else { return }
            self?.levels = out
        }
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                         &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}
