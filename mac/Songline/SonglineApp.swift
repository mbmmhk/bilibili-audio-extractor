import AppKit
import SonglineState
import SonglineUI
import SwiftUI

// App 本体只负责组装，正经代码都在 Packages/SonglineKit 里（见 ARCHITECTURE.md）。

@main
struct SonglineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Songline", id: "main") {
            RootView(model: delegate.model)
        }
        .defaultSize(width: 1180, height: 760)
        .commands { SonglineCommands(model: delegate.model) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = SonglineAppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.start() }
    }

    /// 退出 App 时一并关掉后台的识别服务。
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
