// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StrataMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "StrataMonitor", targets: ["StrataMonitor"]),
        .library(name: "StrataMonitorKit", targets: ["StrataMonitorKit"])
    ],
    targets: [
        // Разбор метрик и модель состояния — без UI, чтобы их можно было тестировать.
        .target(
            name: "StrataMonitorKit",
            path: "Sources/StrataMonitorKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Меню-барное приложение: NSStatusItem, поповер, окно настроек.
        .executableTarget(
            name: "StrataMonitor",
            dependencies: ["StrataMonitorKit"],
            path: "Sources/StrataMonitor",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StrataMonitorKitTests",
            dependencies: ["StrataMonitorKit"],
            path: "Tests/StrataMonitorKitTests",
            resources: [.copy("Fixtures/metrics.json")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
