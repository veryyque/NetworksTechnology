// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MulticastDiscovery",
    products: [
        .executable(name: "MulticastDiscovery", targets: ["MulticastDiscovery"])
    ],
    targets: [
        .executableTarget(
            name: "MulticastDiscovery",
            path: "MulticastDelivery",
            exclude: ["README.md", "MulticastDelivery"]
        )
    ]
)
