import AVFoundation
import Combine

/// Sample-by-sample noise, −1…1. White is flat; pink (Paul Kellet's
/// economical filter) rolls off at −3 dB/oct; brown is leaky-integrated white
/// (−6 dB/oct) — the deep "rumble". Pure value type, tested in the harness.
struct NoiseGenerator {
    enum Kind: String, CaseIterable { case white, pink, brown }

    let kind: Kind
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0
    private var brown = 0.0
    private var rng = SystemRandomNumberGenerator()

    init(_ kind: Kind) { self.kind = kind }

    mutating func next() -> Float {
        let white = Double.random(in: -1...1, using: &rng)
        switch kind {
        case .white:
            return Float(white * 0.5)
        case .pink:
            b0 = 0.99886 * b0 + white * 0.0555179; b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520; b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522; b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            return Float(pink * 0.11)
        case .brown:
            brown = (brown + 0.02 * white) / 1.02
            return Float(brown * 3.5)
        }
    }
}

// Focus sounds: generated white/pink/brown noise from the shelf — no bundled
// audio. Opt-in card (`AppSettings.showFocusSounds`). The engine only exists
// while playing.
final class FocusSoundsManager: ObservableObject {
    static let shared = FocusSoundsManager()

    @Published private(set) var playing: NoiseGenerator.Kind?
    @Published var volume: Float = 0.4 { didSet { engine?.mainMixerNode.outputVolume = volume } }

    private var engine: AVAudioEngine?

    private init() {}

    /// Play `kind`, or stop when it's already the one playing.
    func toggle(_ kind: NoiseGenerator.Kind) {
        let was = playing
        stop()
        if was != kind { start(kind) }
    }

    func stop() {
        engine?.stop()
        engine = nil
        playing = nil
    }

    private func start(_ kind: NoiseGenerator.Kind) {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        // The render block owns its generator; only the audio thread touches it.
        var generator = NoiseGenerator(kind)
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList in
            for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                let samples = buffer.mData!.assumingMemoryBound(to: Float.self)
                for i in 0..<Int(frameCount) { samples[i] = generator.next() }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        do {
            try engine.start()
            self.engine = engine
            playing = kind
        } catch {
            playing = nil
        }
    }
}
