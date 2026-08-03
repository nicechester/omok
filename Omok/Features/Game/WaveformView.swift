import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    let isLocalActive: Bool
    let isOpponentActive: Bool

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            let barWidth = max(1, size.width / CGFloat(max(1, samples.count)))
            let maxHeight = size.height / 2

            var path = Path()

            if samples.isEmpty {
                context.stroke(
                    Path(ellipseIn: CGRect(x: 0, y: midY - 1, width: size.width, height: 2)),
                    with: .color(.blue.opacity(0.3))
                )
                return
            }

            let stride = max(1, samples.count / Int(size.width / 4))
            var isFirstPoint = true

            for (index, sample) in samples.enumerated().stride(by: stride) {
                let x = CGFloat(index) * barWidth
                let normalizedSample = CGFloat(min(sample, 1.0)) * maxHeight

                let barPath = Path(roundedRect: CGRect(
                    x: x,
                    y: midY - normalizedSample,
                    width: barWidth - 1,
                    height: normalizedSample * 2
                ), cornerRadius: barWidth / 2)

                let color: Color = isLocalActive ? .blue : .blue.opacity(0.5)
                context.fill(barPath, with: .color(color))

                if isFirstPoint {
                    path.move(to: CGPoint(x: x, y: midY - normalizedSample))
                    isFirstPoint = false
                } else {
                    path.addLine(to: CGPoint(x: x, y: midY - normalizedSample))
                }
            }

            if !isOpponentActive {
                context.stroke(path, with: .color(.blue.opacity(0.3)), lineWidth: 0.5)
            }
        }
        .background(Color.black.opacity(0.05))
        .cornerRadius(4)
    }
}

#Preview {
    VStack {
        Text("Local audio active")
        WaveformView(
            samples: (0..<100).map { _ in Float.random(in: 0...0.08) },
            isLocalActive: true,
            isOpponentActive: false
        )
        .frame(height: 40)

        Text("Opponent audio active")
        WaveformView(
            samples: (0..<100).map { _ in Float.random(in: 0...0.06) },
            isLocalActive: false,
            isOpponentActive: true
        )
        .frame(height: 40)

        Text("Silent")
        WaveformView(
            samples: (0..<100).map { _ in Float.random(in: 0...0.01) },
            isLocalActive: false,
            isOpponentActive: false
        )
        .frame(height: 40)
    }
    .padding()
}
