// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HeadPointer",
    platforms: [.macOS(.v14)], // CMHeadphoneMotionManager on macOS needs 14+
    targets: [
        .executableTarget(
            name: "HeadPointer",
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist so macOS has a motion usage string for this CLI.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", "Sources/HeadPointer/Info.plist"])
            ]
        )
    ]
)
