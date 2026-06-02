import AppKit

// Menu-bar app: accessory activation policy = no Dock icon (LSUIElement in the bundle).
// Top-level entry runs on the main thread; assert main-actor isolation for the
// @MainActor app delegate.
MainActor.assumeIsolated {
    // Off-screen preview rendering: `Talkty --render [outdir]`.
    if let i = CommandLine.arguments.firstIndex(of: "--render") {
        let outDir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "/tmp/talkty-previews"
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        PreviewRenderer.run(outDir: outDir)
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
