import AppKit
import TalktyKit

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

    // Login-item control/inspection: `Talkty --login-item [on|off|status]`. Must run
    // from the real .app bundle (SMAppService resolves the main bundle).
    if let i = CommandLine.arguments.firstIndex(of: "--login-item") {
        NSApplication.shared.setActivationPolicy(.prohibited)
        switch CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "status" {
        case "on": LoginItemService.setEnabled(true)
        case "off": LoginItemService.setEnabled(false)
        default: break
        }
        print("login-item: status=\(LoginItemService.statusDescription)")
        exit(0)
    }

    // Auto-paste mechanism test: `Talkty --type-text "hello" [delaySeconds]`. After
    // `delay`, inserts the text at the cursor (focus a target first) using the same
    // method the app uses (`autoPasteMethod` defaults key). Needs Accessibility.
    if let i = CommandLine.arguments.firstIndex(of: "--type-text") {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let text = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "Talkty test 123"
        let delay = CommandLine.arguments.count > i + 2 ? (Double(CommandLine.arguments[i + 2]) ?? 0) : 0
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let service = AutoPasteService()   // must outlive the settle timer that restores the clipboard
        print("type-text (\(AutoPasteService.method.rawValue)): \(service.insert(text, keepOnClipboard: nil))")
        // The clipboard restore is queued on the main queue. `run(until:)` returns at once
        // when the loop has no sources, so attach a timer to keep it spinning long enough.
        RunLoop.main.run(until: Date().addingTimeInterval(AutoPasteService.pasteSettleDelay + 0.3))
        exit(0)
    }

    // Test driver: `Talkty --key <keyCode> [option|command|control|shift]...` posts one
    // key press system-wide from the signed bundle (which holds the Accessibility grant),
    // so a script can hit the running app's hotkey (⌥Q = 12 option) or ESC (53) and
    // exercise the real recording flow without a human at the keyboard.
    if let i = CommandLine.arguments.firstIndex(of: "--key"),
       CommandLine.arguments.count > i + 1, let code = UInt16(CommandLine.arguments[i + 1]) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var flags: CGEventFlags = []
        for mod in CommandLine.arguments[(i + 2)...] {
            switch mod {
            case "option": flags.insert(.maskAlternate)
            case "command": flags.insert(.maskCommand)
            case "control": flags.insert(.maskControl)
            case "shift": flags.insert(.maskShift)
            default: break
            }
        }
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) else {
            print("key: failed to create events (Accessibility?)"); exit(1)
        }
        down.flags = flags; up.flags = flags
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
        up.post(tap: .cghidEventTap)
        print("key: posted \(code) \(flags.rawValue)")
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
