import Foundation

struct AudioFrame: Codable {
    let sequence: UInt32
    let samples: [Int16]
    let timestamp: UInt64

    /// Quantize Float samples to Int16 for transmission.
    /// Clamps input to [-1.0, 1.0], then scales to Int16 range.
    static func quantize(_ floatSamples: [Float]) -> [Int16] {
        floatSamples.map { x in
            Int16(max(-1, min(1, x)) * Float(Int16.max))
        }
    }

    /// Dequantize Int16 samples back to Float.
    /// Divides by Int16.max to return to [-1.0, 1.0] range.
    static func dequantize(_ int16Samples: [Int16]) -> [Float] {
        int16Samples.map { x in
            Float(x) / Float(Int16.max)
        }
    }
}
