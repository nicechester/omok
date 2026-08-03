import SwiftUI

struct WaveformView: View {
    let localSamples: [Float]
    let opponentSamples: [Float]
    let isLocalActive: Bool
    let isOpponentActive: Bool

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let maxHeight = size.height * 0.45  // Use most of height for amplitude

            // Draw local waveform (above midline)
            drawWaveform(
                context: context,
                samples: localSamples,
                isActive: isLocalActive,
                size: size,
                midY: midY,
                maxHeight: maxHeight,
                isLocal: true
            )

            // Draw opponent waveform (below midline, mirrored)
            drawWaveform(
                context: context,
                samples: opponentSamples,
                isActive: isOpponentActive,
                size: size,
                midY: midY,
                maxHeight: maxHeight,
                isLocal: false
            )

            // Draw center line
            context.stroke(
                Path(ellipseIn: CGRect(x: 0, y: midY - 1, width: size.width, height: 2)),
                with: .color(.blue.opacity(0.2))
            )
        }
        .background(Color.clear)
        .cornerRadius(4)
    }

    private func drawWaveform(
        context: GraphicsContext,
        samples: [Float],
        isActive: Bool,
        size: CGSize,
        midY: CGFloat,
        maxHeight: CGFloat,
        isLocal: Bool
    ) {
        if samples.isEmpty {
            return
        }

        let barWidth = max(1, size.width / CGFloat(max(1, samples.count)))
        let strideValue = max(1, samples.count / Int(size.width / 4))
        var path = Path()
        var isFirstPoint = true

        let indices = Swift.stride(from: 0, to: samples.count, by: strideValue)
        for index in indices {
            let sample = samples[index]
            let x = CGFloat(index) * barWidth
            let normalizedSample = CGFloat(min(abs(sample), 1.0)) * maxHeight

            // Local: above midline, Opponent: below midline
            let yOffset = isLocal ? (midY - normalizedSample) : (midY + normalizedSample)

            let barPath = Path(roundedRect: CGRect(
                x: x,
                y: isLocal ? (midY - normalizedSample) : midY,
                width: barWidth - 1,
                height: normalizedSample
            ), cornerRadius: barWidth / 2)

            let color: Color = isActive ? .blue : .blue.opacity(0.5)
            context.fill(barPath, with: .color(color))

            if isFirstPoint {
                path.move(to: CGPoint(x: x, y: yOffset))
                isFirstPoint = false
            } else {
                path.addLine(to: CGPoint(x: x, y: yOffset))
            }
        }

        if !isActive {
            context.stroke(path, with: .color(.blue.opacity(0.3)), lineWidth: 0.5)
        }
    }
}

#Preview {
    VStack {
        Text("Local audio active")
        WaveformView(
            localSamples: (0..<100).map { _ in Float.random(in: 0...0.08) },
            opponentSamples: (0..<100).map { _ in Float.random(in: 0...0.02) },
            isLocalActive: true,
            isOpponentActive: false
        )
        .frame(height: 60)

        Text("Opponent audio active")
        WaveformView(
            localSamples: (0..<100).map { _ in Float.random(in: 0...0.02) },
            opponentSamples: (0..<100).map { _ in Float.random(in: 0...0.06) },
            isLocalActive: false,
            isOpponentActive: true
        )
        .frame(height: 60)

        Text("Both active")
        WaveformView(
            localSamples: (0..<100).map { _ in Float.random(in: 0...0.07) },
            opponentSamples: (0..<100).map { _ in Float.random(in: 0...0.05) },
            isLocalActive: true,
            isOpponentActive: true
        )
        .frame(height: 60)

        Text("Silent")
        WaveformView(
            localSamples: (0..<100).map { _ in Float.random(in: 0...0.01) },
            opponentSamples: (0..<100).map { _ in Float.random(in: 0...0.01) },
            isLocalActive: false,
            isOpponentActive: false
        )
        .frame(height: 60)
    }
    .padding()
}
