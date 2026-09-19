// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RecipeCore",
    // macOS is listed only so `swift test` runs on the host; the app is iOS/iPadOS 17+.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RecipeCore", targets: ["RecipeCore"]),
    ],
    targets: [
        .target(name: "RecipeCore"),
        .testTarget(name: "RecipeCoreTests", dependencies: ["RecipeCore"]),
    ],
    swiftLanguageModes: [.v6]
)
