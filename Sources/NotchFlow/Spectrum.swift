import Accelerate
import Foundation

// Turns a window of mono samples into a few 0…1 bar levels. Pure (Accelerate
// only, no audio I/O) so the swiftc harness can feed it synthetic tones.
enum Spectrum {
    static let fftSize = 1024

    private static let dft = try? vDSP.DiscreteFourierTransform(
        count: fftSize, direction: .forward, transformType: .complexComplex, ofType: Float.self)
    private static let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                            count: fftSize, isHalfWindow: false)

    /// `bands` levels, log-spaced from ~60 Hz to ~12 kHz, each 0…1 on a
    /// −60…0 dBFS scale. `samples` shorter than `fftSize` are zero-padded.
    static func levels(_ samples: [Float], sampleRate: Double, bands: Int) -> [Float] {
        guard let dft, bands > 0 else { return [] }
        var real = [Float](repeating: 0, count: fftSize)
        for i in 0..<min(fftSize, samples.count) { real[i] = samples[i] * window[i] }
        let imag = [Float](repeating: 0, count: fftSize)
        let (outReal, outImag) = dft.transform(real: real, imaginary: imag)

        // Magnitude per bin over the positive half, normalized so a full-scale
        // sine reads ~0 dBFS (Hann window halves the coherent gain).
        let half = fftSize / 2
        let scale = 4 / Float(fftSize)
        var mags = [Float](repeating: 0, count: half)
        for i in 0..<half { mags[i] = (outReal[i] * outReal[i] + outImag[i] * outImag[i]).squareRoot() * scale }

        let binHz = sampleRate / Double(fftSize)
        let lo = 60.0, hi = min(12_000, sampleRate / 2)
        return (0..<bands).map { b in
            let f0 = lo * pow(hi / lo, Double(b) / Double(bands))
            let f1 = lo * pow(hi / lo, Double(b + 1) / Double(bands))
            let i0 = max(1, Int(f0 / binHz)), i1 = max(i0 + 1, min(half, Int(f1 / binHz)))
            let peak = mags[i0..<i1].max() ?? 0
            let db = 20 * log10(max(peak, 1e-6))
            return min(1, max(0, (db + 60) / 60))
        }
    }
}
