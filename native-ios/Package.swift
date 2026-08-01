// swift-tools-version:5.9
// Package SPM per la SOLA logica pura (FiloCore) + test eseguibili su Linux
// con `swift test`. I sorgenti SwiftUI (Sources/App) NON fanno parte del
// package: li usa esclusivamente project.yml (XcodeGen) per il target app.
import PackageDescription

let package = Package(
    name: "FiloCore",
    products: [
        .library(name: "FiloCore", targets: ["FiloCore"])
    ],
    targets: [
        .target(
            name: "FiloCore",
            path: "Sources/FiloCore"
        ),
        .testTarget(
            name: "FiloCoreTests",
            dependencies: ["FiloCore"],
            path: "Tests/FiloCoreTests",
            resources: [
                .copy("reference.json")
            ]
        )
    ]
)
