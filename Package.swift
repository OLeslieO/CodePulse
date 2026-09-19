// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexSignal",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexSignal", targets: ["SignalApp"]),
        .executable(name: "signalctl", targets: ["SignalCLI"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "SignalCore"),
        .target(name: "SignalMac", dependencies: ["SignalCore", "CSQLite"],
                linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("Security")]),
        .executableTarget(name: "SignalApp", dependencies: ["SignalCore", "SignalMac"]),
        .executableTarget(name: "SignalCLI", dependencies: ["SignalCore", "SignalMac"]),
        .testTarget(name: "SignalCoreTests", dependencies: ["SignalCore", "SignalMac", "CSQLite"])
    ],
    swiftLanguageModes: [.v5]
)
