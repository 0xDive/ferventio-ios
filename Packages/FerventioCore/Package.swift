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
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.8.0"),
    ],
    targets: [
        .target(name: "FerventioDomain"),
        .target(name: "FerventioNetworking", dependencies: ["FerventioDomain"]),
        .target(
            name: "FerventioPersistence",
            dependencies: [
                "FerventioDomain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(name: "FerventioSupport", dependencies: ["FerventioDomain"]),
        .testTarget(name: "FerventioDomainTests", dependencies: ["FerventioDomain"]),
        .testTarget(name: "FerventioNetworkingTests", dependencies: ["FerventioDomain", "FerventioNetworking"]),
        .testTarget(name: "FerventioPersistenceTests", dependencies: ["FerventioDomain", "FerventioPersistence"]),
        .testTarget(name: "FerventioSupportTests", dependencies: ["FerventioDomain", "FerventioSupport"]),
    ]
)
