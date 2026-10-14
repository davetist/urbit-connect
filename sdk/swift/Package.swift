// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "UrbitConnect", platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "UrbitConnect", targets: ["UrbitConnect"])],
    targets: [.systemLibrary(name: "CSQLite"), .target(name: "UrbitConnect", dependencies: ["CSQLite"]), .target(name: "SQLiteFaultHelper", path: "Tests/SQLiteFaultHelper", linkerSettings: [.linkedLibrary("sqlite3")]), .testTarget(name: "UrbitConnectTests", dependencies: ["UrbitConnect", "SQLiteFaultHelper"], resources: [.copy("Fixtures")])],
    swiftLanguageModes: [.v6]
)
