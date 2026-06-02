import SwiftUI
import TalktyKit

/// The floating recording pill: record dot + audio-reactive waveform + timer.
/// Colors follow the original: red (recording) → purple (transcribing) → green (copied).
struct OverlayView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            RecordDot(color: state.accent, active: state.recordingState == .listening)
            WaveformBars(level: CGFloat(state.audioLevel),
                         color: state.accent,
                         active: state.recordingState == .listening)
                .frame(width: 26, height: 18)
            Text(label)
                .font(Theme.mono(13, .medium))
                .foregroundStyle(state.recordingState == .copied ? Theme.green : Theme.textPrimary)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x121214, alpha: 0.82))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 4)
        .fixedSize()
    }

    private var label: String {
        switch state.recordingState {
        case .transcribing: return "···"
        case .copied: return "Copied"
        case .cancelled: return "Cancelled"
        default: return state.elapsedDisplay
        }
    }
}

private struct RecordDot: View {
    let color: Color
    let active: Bool
    @State private var pulse = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .opacity(active ? (pulse ? 0.45 : 1) : 1)
            .animation(active ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { pulse = active }
            .onChange(of: active) { _, v in pulse = v }
    }
}

/// Three bars that react to the live audio level, with subtle organic motion.
private struct WaveformBars: View {
    let level: CGFloat
    let color: Color
    let active: Bool

    private let bases: [CGFloat] = [0.42, 0.85, 0.55]   // relative idle heights

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: barHeight(i, t))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func barHeight(_ i: Int, _ t: TimeInterval) -> CGFloat {
        let maxH: CGFloat = 18, minH: CGFloat = 4
        let wobble = active ? (sin(t * 7 + Double(i) * 1.7) * 0.18 + 0.18) : 0
        let driven = active ? (bases[i] * 0.45 + level * 1.25 + CGFloat(wobble)) : bases[i] * 0.4
        return max(minH, min(maxH, driven * maxH))
    }
}
