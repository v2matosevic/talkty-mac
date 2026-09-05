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
                .foregroundStyle(labelColor)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: state.recordingState == .failed ? 150 : nil)
                .fixedSize(horizontal: state.recordingState != .failed, vertical: true)
            PromptToggle(state: state)
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
        .fixedSize()
        .help(state.recordingState == .listening ? "Esc cancels" : "")
    }

    private var label: String {
        switch state.recordingState {
        case .transcribing: return state.promptingMode ? "Prompting…" : "···"
        case .copied: return "Copied"
        case .cancelled: return "Cancelled"
        case .failed: return state.statusText
        default: return state.elapsedDisplay
        }
    }

    private var labelColor: Color {
        switch state.recordingState {
        case .copied: return Theme.green
        case .failed: return Theme.orange
        case .transcribing where state.promptingMode: return Theme.purple
        default: return Theme.textPrimary
        }
    }
}

/// The "Prompting" toggle: a sparkle glyph in a fixed slot at the right of the pill.
/// Hidden until you hover the pill (or while active), so plain dictation stays clean.
/// Tapped, the current take's transcription is expanded into a coding-agent prompt.
/// Purple = on. Resets each recording.
private struct PromptToggle: View {
    @ObservedObject var state: AppState

    /// Only meaningful while a take is in progress (you arm it before stopping).
    private var togglable: Bool {
        state.recordingState == .listening || state.recordingState == .transcribing
    }
    private var revealed: Bool { togglable && (state.overlayHovering || state.promptingMode) }

    var body: some View {
        Button {
            state.promptingMode.toggle()
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.promptingMode ? Theme.purple : Theme.textMuted)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Prompting: turn this dictation into a structured prompt for a coding AI agent")
        .opacity(revealed ? 1 : 0)
        .allowsHitTesting(revealed)
        // Reserve the 18pt slot for the whole take (so revealing on hover never shifts
        // the pill under the cursor), but collapse it entirely outside a take so plain
        // dictation has no empty gap on the right.
        .frame(width: togglable ? 18 : 0, height: 18)
        .clipped()
        .animation(.easeInOut(duration: 0.15), value: revealed)
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
        // Paused when not listening: the panel stays visible through the transcribing/
        // copied tail, and ~16 Hz redraws of static bars would land exactly while the
        // CPU/GPU is busiest with the model.
        TimelineView(.animation(minimumInterval: 0.06, paused: !active)) { timeline in
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
