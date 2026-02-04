// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoParentingApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "CoParentingApp",
            targets: ["CoParentingApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/kvyatkovskys/KVKCalendar.git", from: "0.6.0"),
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "CoParentingApp",
            dependencies: [
                "KVKCalendar",
                "SwiftAnthropic"
            ],
            path: "CoParentingApp",
            exclude: ["Resources/Info.plist", "Resources/CoParentingApp.entitlements", "Resources/Assets.xcassets"],
            swiftSettings: [.define("SPM_BUILD")]
        ),
        .testTarget(
            name: "CoParentingAppTests",
            dependencies: ["CoParentingApp", "SwiftAnthropic"],
            path: "CoParentingAppTests"
        ),
    ]
)
