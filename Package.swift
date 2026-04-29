// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Moveresize",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "moveresize", targets: ["Moveresize"])
    ],
    targets: [
        .executableTarget(
            name: "Moveresize",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)