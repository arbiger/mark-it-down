// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkItDown",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "markitdown", targets: ["MarkItDown"])
    ],
    targets: [
        .executableTarget(
            name: "MarkItDown",
            path: "Sources/MarkItDown"
        )
    ]
)
