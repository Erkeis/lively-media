// swift-tools-version: 6.0
// [Intent] Swift Package defining the modular core subsystems for iOS & iPadOS Media Player
import PackageDescription

let package = Package(
    name: "LivelyMediaCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CoreStorage", targets: ["CoreStorage"]),
        .library(name: "MetadataEngine", targets: ["MetadataEngine"]),
        .library(name: "TransferServer", targets: ["TransferServer"]),
        .library(name: "FileManagerCore", targets: ["FileManagerCore"]),
        .library(name: "PlaybackEngine", targets: ["PlaybackEngine"]),
        .library(name: "PlayerUI", targets: ["PlayerUI"]),
        .library(name: "CastEngine", targets: ["CastEngine"]),
        .library(name: "TestServerClient", targets: ["TestServerClient"]),
        .library(name: "WebSnifferEngine", targets: ["WebSnifferEngine"]),
        .library(name: "DownloadManagerEngine", targets: ["DownloadManagerEngine"]),
        .library(name: "PodcastEngine", targets: ["PodcastEngine"])
    ],
    dependencies: [
        // GRDB.swift for SQLite concurrent storage and relational queries
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        // FlyingFox for lightweight async Swift HTTP server (Wi-Fi Web Transfer & Cast Bridge)
        .package(url: "https://github.com/swhitty/FlyingFox.git", from: "0.16.0")
    ],
    targets: [
        // 1. Core Storage Layer (SQLite / GRDB)
        .target(
            name: "CoreStorage",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/CoreStorage"
        ),
        .testTarget(
            name: "CoreStorageTests",
            dependencies: [
                "CoreStorage",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Tests/CoreStorageTests"
        ),

        // 2. Metadata Extraction & Waveform Engine
        .target(
            name: "MetadataEngine",
            dependencies: ["CoreStorage"],
            path: "Sources/MetadataEngine"
        ),
        .testTarget(
            name: "MetadataEngineTests",
            dependencies: ["MetadataEngine", "CoreStorage"],
            path: "Tests/MetadataEngineTests"
        ),

        // 3. Embedded Wi-Fi Web Transfer & Cast HTTP Server
        .target(
            name: "TransferServer",
            dependencies: [
                "CoreStorage",
                .product(name: "FlyingFox", package: "FlyingFox")
            ],
            path: "Sources/TransferServer"
        ),
        .testTarget(
            name: "TransferServerTests",
            dependencies: [
                "TransferServer",
                .product(name: "FlyingFox", package: "FlyingFox")
            ],
            path: "Tests/TransferServerTests"
        ),

        // 4. File Ingestion, Sandbox Directory Watcher & Security-Scoped Bookmarks
        .target(
            name: "FileManagerCore",
            dependencies: ["CoreStorage", "MetadataEngine"],
            path: "Sources/FileManagerCore"
        ),
        .testTarget(
            name: "FileManagerCoreTests",
            dependencies: ["FileManagerCore", "CoreStorage"],
            path: "Tests/FileManagerCoreTests"
        ),

        // 5. Dual Playback Engine Subsystem (AVPlayer + KSPlayer/Metal Adapter)
        .target(
            name: "PlaybackEngine",
            dependencies: ["CoreStorage", "MetadataEngine"],
            path: "Sources/PlaybackEngine"
        ),
        .testTarget(
            name: "PlaybackEngineTests",
            dependencies: ["PlaybackEngine", "CoreStorage"],
            path: "Tests/PlaybackEngineTests"
        ),

        // 6. SwiftUI Obsidian Studio Presentation & Interaction Layer
        .target(
            name: "PlayerUI",
            dependencies: [
                "PlaybackEngine",
                "CoreStorage",
                "MetadataEngine",
                "TransferServer",
                "FileManagerCore",
                "CastEngine",
                "WebSnifferEngine",
                "DownloadManagerEngine"
            ],
            path: "Sources/PlayerUI"
        ),
        .testTarget(
            name: "PlayerUITests",
            dependencies: ["PlayerUI", "PlaybackEngine", "CoreStorage"],
            path: "Tests/PlayerUITests"
        ),

        // 7. Casting & Routing Subsystem (AirPlay 2 + Google Cast HTTP Bridge)
        .target(
            name: "CastEngine",
            dependencies: ["PlaybackEngine", "CoreStorage", "TransferServer"],
            path: "Sources/CastEngine"
        ),
        .testTarget(
            name: "CastEngineTests",
            dependencies: ["CastEngine", "CoreStorage"],
            path: "Tests/CastEngineTests"
        ),

        // 8. Linux Test Server Client (WebDAV / HTTP Range / Mock Podcast Fixtures)
        .target(
            name: "TestServerClient",
            dependencies: ["CoreStorage", "MetadataEngine"],
            path: "Sources/TestServerClient"
        ),
        .testTarget(
            name: "TestServerClientTests",
            dependencies: ["TestServerClient", "CoreStorage"],
            path: "Tests/TestServerClientTests"
        ),

        // 9. In-App Web Browser & Media Stream Sniffer
        .target(
            name: "WebSnifferEngine",
            dependencies: ["CoreStorage", "MetadataEngine", "PlaybackEngine", "CastEngine"],
            path: "Sources/WebSnifferEngine"
        ),
        .testTarget(
            name: "WebSnifferEngineTests",
            dependencies: ["WebSnifferEngine", "CoreStorage"],
            path: "Tests/WebSnifferEngineTests"
        ),

        // 10. Background URLSession Download Manager
        .target(
            name: "DownloadManagerEngine",
            dependencies: ["CoreStorage", "MetadataEngine"],
            path: "Sources/DownloadManagerEngine"
        ),
        .testTarget(
            name: "DownloadManagerEngineTests",
            dependencies: ["DownloadManagerEngine", "CoreStorage"],
            path: "Tests/DownloadManagerEngineTests"
        ),

        // 11. Modular Podcast RSS Feed Parser
        .target(
            name: "PodcastEngine",
            dependencies: ["CoreStorage"],
            path: "Sources/PodcastEngine"
        ),
        .testTarget(
            name: "PodcastEngineTests",
            dependencies: ["PodcastEngine", "CoreStorage"],
            path: "Tests/PodcastEngineTests"
        )
    ]
)
