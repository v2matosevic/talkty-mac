import SwiftUI
import AppKit
import TalktyKit

// MARK: Onboarding

struct OnboardingView: View {
    let hotkey: String
    let onOpenSettings: () -> Void
    let onGetStarted: () -> Void

    private struct Step { let n: Int; let title: String; let detail: String }
    private var steps: [Step] {
        [Step(n: 1, title: "Download a model", detail: "Open Settings and download a Whisper model. Large v3 Turbo is the all-round pick; Base is fine for quick notes."),
         Step(n: 2, title: "Press \(hotkey) anywhere", detail: "From any app, press your shortcut and start speaking. Esc cancels."),
         Step(n: 3, title: "Press again to finish", detail: "Your speech is transcribed on-device and copied to the clipboard, or pasted at the cursor with auto-paste on. Hover the pill and tap ✦ to turn a take into a coding-agent prompt.")]
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "waveform").font(.system(size: 30)).foregroundStyle(Theme.purple)
                Text("Welcome to Talkty").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("Private, on-device speech to text.").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
            .background(Theme.purple.opacity(0.08))

            VStack(alignment: .leading, spacing: 18) {
                ForEach(steps, id: \.n) { step in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(Theme.purple.opacity(0.18)).frame(width: 28, height: 28)
                            Text("\(step.n)").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.purple)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            Text(step.detail).font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .padding(28)

            Spacer()
            HStack {
                SecondaryButton(title: "Open Settings", action: onOpenSettings)
                Spacer()
                PrimaryButton(title: "Get Started", action: onGetStarted)
            }
            .padding(20)
        }
        .frame(width: 500, height: 420)
        .background(Theme.bg)
    }
}

// MARK: About

struct AboutView: View {
    let version: String
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(LinearGradient(
                    colors: [Theme.purple, Theme.purpleAlt], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                Image(systemName: "waveform").font(.system(size: 30, weight: .medium)).foregroundStyle(.white)
            }
            Text("Talkty").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Version \(version)").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
            Text("Local speech-to-text powered by Whisper.\nFast, private, and fully on-device.")
                .multilineTextAlignment(.center)
                .font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                .padding(.horizontal, 30)
            Spacer()
            HStack(spacing: 4) {
                Text("© 2026 Version2").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                Text("·").foregroundStyle(Theme.textFaint)
                Button("GitHub") { if let u = URL(string: Constants.repoURL) { NSWorkspace.shared.open(u) } }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.purple)
            }
            .padding(.bottom, 18)
        }
        .frame(width: 400, height: 340)
        .background(Theme.bg)
    }
}
