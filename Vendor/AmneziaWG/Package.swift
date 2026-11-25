// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WireGuardKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "WireGuardKit", targets: ["WireGuardKit"])
    ],
    targets: [
        .target(name: "WireGuardKit", dependencies: ["WireGuardKitC", "WireGuardKitGo"]),
        .target(name: "WireGuardKitC", publicHeadersPath: "."),
        .target(
            name: "WireGuardKitGo",
            exclude: ["api-apple.go", "go.mod", "go.sum", "goruntime-boottime-over-monotonic.diff"],
            publicHeadersPath: ".",
            linkerSettings: [
                .linkedLibrary("wg-go"),
                .linkedLibrary("resolv"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .testTarget(name: "WireGuardKitTests", dependencies: ["WireGuardKit"])
    ]
)
