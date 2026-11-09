// swift-tools-version:5.9
// VartaAPI Desk for iPhone and iPad (DK25): the business's website chat inside
// its own iOS app, drawn with Apple's own UIKit screens. No other libraries.
import PackageDescription

let package = Package(
    name: "VartaDesk",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "VartaDesk", targets: ["VartaDesk"]),
    ],
    targets: [
        .target(name: "VartaDesk", path: "Sources/VartaDesk"),
    ]
)
