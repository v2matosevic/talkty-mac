// swift-tools-version:5.9
import PackageDescription
import Foundation

// Resolve the vendored whisper.cpp static-lib prefix relative to this manifest,
// so the package stays portable to wherever it's checked out.
let pkgDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let whisperLib = "\(pkgDir)/Vendor/whisper-install/lib"

let whisperLink: [LinkerSetting] = [
    .unsafeFlags([
        "-L\(whisperLib)",
        // dependents before dependencies; ggml-base is the most-depended-upon
        "-lwhisper",
        "-lggml",
        "-lggml-cpu",
        "-lggml-blas",
        "-lggml-metal",
        "-lggml-base",
    ]),
    .linkedFramework("Metal"),
    .linkedFramework("MetalKit"),
    .linkedFramework("Accelerate"),
    .linkedFramework("Foundation"),
    .linkedFramework("AVFoundation"),
    .linkedLibrary("c++"),
]

let package = Package(
    name: "Talkty",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper"
        ),
        .target(
            name: "TalktyKit",
            dependencies: ["CWhisper"],
            path: "Sources/TalktyKit",
            linkerSettings: whisperLink
        ),
        .executableTarget(
            name: "smoke",
            dependencies: ["TalktyKit"],
            path: "Sources/smoke"
        ),
    ]
)
