// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BarcodeDecoding",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "BarcodeDecoding", targets: ["BarcodeDecoding"]),
    ],
    targets: [
        .target(
            name: "BarcodeDecoding",
            swiftSettings: [
                // Pixel loops run 20-50x slower unoptimized, so the decoder
                // is optimized in Debug builds too.
                .unsafeFlags(["-O"], .when(configuration: .debug)),
            ]
        ),
        .testTarget(name: "BarcodeDecodingTests", dependencies: ["BarcodeDecoding"]),
    ]
)
