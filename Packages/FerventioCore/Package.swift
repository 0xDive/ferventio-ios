// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FerventioCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "FerventioDomain", targets: ["FerventioDomain"]),
        .library(name: "FerventioNetworking", targets: ["FerventioNetworking"]),
        .library(name: "FerventioPersistence", targets: ["FerventioPersistence"]),
        .library(name: "FerventioSupport", targets: ["FerventioSupport"]),
    ],
    targets: [
        .target(name: "FerventioDomain"),
        .target(name: "FerventioNetworking", dependencies: ["FerventioDomain"]),
        .target(name: "FerventioPersistence", dependencies: ["FerventioDomain"]),
        .target(name: "FerventioSupport", dependencies: ["FerventioDomain"]),
        .testTarget(name: "FerventioDomainTests", dependencies: ["FerventioDomain"]),
        .testTarget(name: "FerventioNetworkingTests", dependencies: ["FerventioNetworking"]),
        .testTarget(name: "FerventioSupportTests", dependencies: ["FerventioDomain", "FerventioSupport"]),
    ]
)
