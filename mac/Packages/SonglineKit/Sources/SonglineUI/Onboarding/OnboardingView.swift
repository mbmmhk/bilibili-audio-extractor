import AppKit
import SonglineBackend
import SonglineState
import SwiftUI

/// 后端还没就绪时显示：首次安装进度、启动中、或者出错了。
struct OnboardingView: View {
    var backend: BackendRuntime
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Theme.accent).frame(width: 72, height: 72)
                Image(systemName: "waveform").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
            }
            Text("Songline").font(.largeTitle.bold())
            content.frame(maxWidth: 420)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch backend.state {
        case .idle, .starting, .running:
            ProgressView().controlSize(.small)
            Text("正在启动识别服务…").foregroundStyle(.secondary)

        case let .installing(step, progress):
            Text("首次使用，正在准备（只需一次）").font(.headline)
            Group {
                if let progress { ProgressView(value: progress) } else { ProgressView().progressViewStyle(.linear) }
            }
            .tint(Theme.accent)
            Text(step).font(.callout).foregroundStyle(.secondary).monospacedDigit()

        case let .failed(message, detail):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            HStack {
                Button("重试", action: retry).buttonStyle(.borderedProminent).tint(Theme.accent)
                Button("打开日志") { NSWorkspace.shared.open(backend.paths.log) }
            }
            DisclosureGroup("详细信息") {
                ScrollView {
                    Text(detail).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            .font(.callout)
        }
    }
}
