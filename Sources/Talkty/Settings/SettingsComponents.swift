import AppKit
import SwiftUI

/// Shared settings UI atoms, styled to the Zinc design language.

/// AppKit-backed slider. The settings window is movable-by-background and SwiftUI's
/// Slider doesn't refuse `mouseDownCanMoveWindow` — dragging its knob drags the whole
/// window. A real NSSlider refuses it by AppKit contract, so the knob drags normally.
struct NativeSlider: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.controlSize = .small
        slider.isContinuous = true
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.binding = $value
        if abs(slider.doubleValue - value) > 0.0001 { slider.doubleValue = value }
    }

    func makeCoordinator() -> Coordinator { Coordinator($value) }

    @MainActor final class Coordinator: NSObject {   // NSSlider fires its action on main
        var binding: Binding<Double>
        init(_ binding: Binding<Double>) { self.binding = binding }
        @objc func changed(_ sender: NSSlider) { binding.wrappedValue = sender.doubleValue }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textFaint)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border, lineWidth: 1))
    }
}

struct CheckRow: View {
    let label: String
    @Binding var isOn: Bool
    var subtitle: String? = nil
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isOn ? Theme.purple : Color.clear)
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isOn ? Theme.purple : Theme.textFaint, lineWidth: 1.5)
                    if isOn {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textMuted) }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                .padding(.horizontal, 22).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white))
        }.buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

/// A thin horizontal level/progress bar.
struct LevelBar: View {
    let fraction: Double
    var color: Color = Theme.green
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule().fill(color).frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}
