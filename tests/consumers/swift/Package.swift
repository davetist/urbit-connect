// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "NotesConsumer", platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "NotesConsumer", targets: ["NotesConsumer"])],
    dependencies: [.package(name: "UrbitConnect", path: "../../..")],
    targets: [
        .target(name: "NotesConsumer", dependencies: [.product(name: "UrbitConnect", package: "UrbitConnect")]),
        .testTarget(name: "NotesConsumerTests", dependencies: ["NotesConsumer"])
    ], swiftLanguageModes: [.v6]
)
