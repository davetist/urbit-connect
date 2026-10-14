// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UrbitConnect",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "UrbitConnect", targets: ["UrbitConnect"])],
    targets: [
        .systemLibrary(name: "CSQLite", path: "sdk/swift/Sources/CSQLite"),
        .target(name: "UrbitConnect", dependencies: ["CSQLite"], path: "sdk/swift/Sources/UrbitConnect"),
        .target(name: "SQLiteFaultHelper", path: "sdk/swift/Tests/SQLiteFaultHelper", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "UrbitConnectTests", dependencies: ["UrbitConnect", "SQLiteFaultHelper"], path: "sdk/swift/Tests/UrbitConnectTests", resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v6]
)
