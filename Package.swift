// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftTreeSitter",
    products: [
        .library(
            name: "SwiftTreeSitter",
            targets: ["TreeSitter", "SwiftTreeSitter"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TreeSitter",
            dependencies: [],
            path: "Sources/TreeSitter",
            exclude: [
                "src",
                "./src/unicode/ICU_SHA",
                "./src/unicode/LICENSE",
                "./src/unicode/README.md",
            ]
        ),
        .target(
            name: "SwiftTreeSitter",
            dependencies: ["TreeSitter"],
            path: "Sources/SwiftTreeSitter"
        ),
        .target(name: "TreeSitterJavaScript", exclude: ["README.md"]),
        .testTarget(
            name: "SwiftTreeSitterTests",
            dependencies: [
                "SwiftTreeSitter",
                "TreeSitterJavaScript"
            ]
        ),
    ]
)
