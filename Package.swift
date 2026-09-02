// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacWidgetDrive",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacWidgetDrive",
            path: "Sources/MacWidgetDrive",
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
