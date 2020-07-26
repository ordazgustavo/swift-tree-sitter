// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftTreeSitter",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SwiftTreeSitter",
            targets: ["TreeSitter", "SwiftTreeSitter"]
        ),
        .library(
            name: "TreeSitterJavaScript",
            type: .dynamic,
            targets: ["TreeSitterJavaScript"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "file:///Users/gustavoordaz/Developer/TreeSitterJSON", from: "0.0.3"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
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
            name: "TreeSitterJavaScript",
            dependencies: [],
            path: "Sources/TreeSitterJavaScript"
        ),
        .target(
            name: "SwiftTreeSitter",
            dependencies: ["TreeSitter"],
            path: "Sources/SwiftTreeSitter"
        ),
        .testTarget(
            name: "SwiftTreeSitterTests",
            dependencies: [
                "SwiftTreeSitter",
                "TreeSitterJavaScript",
                .product(name: "TreeSitterJSON", package: "TreeSitterJSON"),
            ]
        ),
    ]
)
