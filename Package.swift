// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MDCApps",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MDCUI", targets: ["MDCUI"])
    ],
    targets: [
        .executableTarget(
            name: "MDCUI",
            path: "macos/MDCUI/Sources"
        )
    ]
)
