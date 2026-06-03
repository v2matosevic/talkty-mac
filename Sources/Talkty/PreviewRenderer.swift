import AppKit
import SwiftUI
import TalktyKit

/// Off-screen rendering of key views to PNGs (via ImageRenderer) so the UI can be
/// inspected without a display or Screen Recording permission. Invoked with
/// `Talkty --render [outdir]`. Note: AppKit-backed controls (Picker/TextEditor)
/// may render blank — this verifies the custom-drawn layout/colors, not those.
@MainActor
enum PreviewRenderer {
    static func run(outDir: String) {
        let dir = URL(fileURLWithPath: outDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = SettingsStore()
        let vm = SettingsViewModel(store: store, onApply: {})
        let models = ModelManager()
        // Render the sections directly (ImageRenderer doesn't lay out ScrollView content).
        render(ZStack(alignment: .top) {
                   Theme.bg
                   SettingsSections(vm: vm, models: models).padding(20)
               },
               size: CGSize(width: 440, height: 1180), name: "settings", dir: dir)

        render(overlay(.listening, level: 0.6, elapsed: 12),
               size: CGSize(width: 240, height: 64), name: "overlay-listening", dir: dir)
        render(overlay(.transcribing, level: 0, elapsed: 0),
               size: CGSize(width: 240, height: 64), name: "overlay-transcribing", dir: dir)
        render(overlay(.copied, level: 0, elapsed: 0),
               size: CGSize(width: 240, height: 64), name: "overlay-copied", dir: dir)

        // Main window (with update banner + sample history)
        let mainState = AppState()
        mainState.recordingState = .idle; mainState.modelLoaded = true
        mainState.updateAvailable = UpdateInfo(latestVersion: "1.0.9", downloadURL: "", releaseNotes: "")
        let mainVM = MainViewModel(history: HistoryStore())
        mainVM.history = [
            HistoryEntry(text: "Let me refactor the authentication middleware.", durationSeconds: 1.3),
            HistoryEntry(text: "Deploy the staging branch to Vercel.", durationSeconds: 0.9),
            HistoryEntry(text: "Add a Postgres index on the users table.", durationSeconds: 1.1),
        ]
        render(MainView(state: mainState, vm: mainVM, onToggle: {}, onSettings: {}),
               size: CGSize(width: 380, height: 460), name: "main", dir: dir)

        render(OnboardingView(hotkey: "⌥Q", onOpenSettings: {}, onGetStarted: {}),
               size: CGSize(width: 500, height: 420), name: "onboarding", dir: dir)
        render(AboutView(version: "1.0.0"),
               size: CGSize(width: 400, height: 340), name: "about", dir: dir)

        render(IconView(), size: CGSize(width: 1024, height: 1024), name: "icon_1024", dir: dir)

        print("rendered previews to \(outDir)")
    }

    private static func overlay(_ rs: RecordingState, level: Float, elapsed: TimeInterval) -> some View {
        let s = AppState()
        s.recordingState = rs; s.audioLevel = level; s.elapsed = elapsed
        return ZStack { Color(hex: 0x2A2A30); OverlayView(state: s) }
    }

    /// The app icon: a deep violet macOS squircle (824 in a 1024 canvas, continuous
    /// corners — Apple's icon grid) with a lit-from-above sheen, a glass rim
    /// highlight, and a raised waveform glyph so it reads native rather than flat.
    struct IconView: View {
        private var squircle: RoundedRectangle { RoundedRectangle(cornerRadius: 185, style: .continuous) }
        var body: some View {
            ZStack {
                squircle
                    .fill(LinearGradient(stops: [
                        .init(color: Color(hex: 0x8E70F2), location: 0.0),
                        .init(color: Color(hex: 0x6E56CF), location: 0.52),
                        .init(color: Color(hex: 0x4B37AE), location: 1.0),
                    ], startPoint: .top, endPoint: .bottom))
                    .frame(width: 824, height: 824)
                    // Lit-from-above sheen.
                    .overlay(
                        squircle
                            .fill(RadialGradient(colors: [.white.opacity(0.30), .white.opacity(0)],
                                                 center: UnitPoint(x: 0.5, y: -0.08),
                                                 startRadius: 0, endRadius: 640))
                            .frame(width: 824, height: 824)
                    )
                    // Glass rim highlight along the top edge.
                    .overlay(
                        squircle
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04)],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 2.5)
                            .frame(width: 824, height: 824)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 34, y: 22)

                HStack(spacing: 30) {
                    bar(196); bar(330); bar(474); bar(566); bar(474); bar(330); bar(196)
                }
                .shadow(color: Color(hex: 0x2A1C66).opacity(0.40), radius: 12, y: 7)
            }
            .frame(width: 1024, height: 1024)
        }
        private func bar(_ h: CGFloat) -> some View {
            Capsule()
                .fill(LinearGradient(colors: [.white, .white.opacity(0.85)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: h)
        }
    }

    private static func render(_ view: some View, size: CGSize, name: String, dir: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else {
            print("failed to render \(name)"); return
        }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
