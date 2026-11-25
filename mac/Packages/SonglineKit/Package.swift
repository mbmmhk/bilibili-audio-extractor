// swift-tools-version: 6.0
// SonglineKit：Songline for Mac 的全部代码。模块划分见 mac/ARCHITECTURE.md。
import PackageDescription

let package = Package(
    name: "SonglineKit",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        // App 用到这两个：界面，以及界面背后的状态（SonglineAppModel）。
        .library(name: "SonglineUI", targets: ["SonglineUI"]),
        .library(name: "SonglineState", targets: ["SonglineState"]),
    ],
    targets: [
        .target(name: "SonglineCore"),
        .target(name: "SonglineAPI", dependencies: ["SonglineCore"]),
        .target(name: "SonglineBackend"),
        .target(name: "SonglinePlayer", dependencies: ["SonglineCore"]),
        .target(name: "SonglineStore", dependencies: ["SonglineCore"]),
        // App 级状态：把后端、接口、播放器串起来，界面只读写它。不含任何视图。
        .target(
            name: "SonglineState",
            dependencies: ["SonglineCore", "SonglineAPI", "SonglineBackend", "SonglinePlayer", "SonglineStore"]
        ),
        // 只有 SwiftUI 视图。
        .target(
            name: "SonglineUI",
            dependencies: ["SonglineState", "SonglineCore", "SonglineAPI", "SonglineBackend", "SonglinePlayer", "SonglineStore"]
        ),

        .testTarget(name: "SonglineCoreTests", dependencies: ["SonglineCore"]),
        .testTarget(name: "SonglineAPITests", dependencies: ["SonglineAPI"]),
        .testTarget(name: "SonglineBackendTests", dependencies: ["SonglineBackend"]),
        .testTarget(name: "SonglineStoreTests", dependencies: ["SonglineStore"]),
        .testTarget(name: "SonglineStateTests", dependencies: ["SonglineState", "SonglineAPI", "SonglineStore"]),
    ]
)
