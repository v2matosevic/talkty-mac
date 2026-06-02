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

        print("rendered previews to \(outDir)")
    }

    private static func overlay(_ rs: RecordingState, level: Float, elapsed: TimeInterval) -> some View {
        let s = AppState()
        s.recordingState = rs; s.audioLevel = level; s.elapsed = elapsed
        return ZStack { Color(hex: 0x2A2A30); OverlayView(state: s) }
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
