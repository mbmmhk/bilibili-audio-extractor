import AppKit
import SonglineCore
import SonglineState
import SwiftUI

/// 识别一场新的直播回放。
struct RecognizeView: View {
    var library: LibraryModel
    @State private var text = ""
    @AppStorage("shazam") private var shazam = true
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("这场直播唱了哪些歌？").font(.system(size: 28, weight: .bold))
            Text("粘贴 B 站视频链接，自动听歌词、查歌名，生成可以直接播放的歌单。翻唱、弹唱、直播回放都可以。")
                .foregroundStyle(.secondary)

            HStack {
                TextField("https://www.bilibili.com/video/BV…  或 b23.tv 短链 / 分享文字", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focused)
                    .onSubmit(submit)
                Button(action: submit) {
                    if busy { ProgressView().controlSize(.small) } else { Text("开始识别") }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }

            Toggle("音频指纹交叉核对（更准，多花几分钟）", isOn: $shazam)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        }
        .frame(maxWidth: 620)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            focused = true
            // 剪贴板里正好是 B 站链接，就帮忙填上。
            if text.isEmpty, let clip = NSPasteboard.general.string(forType: .string), BiliLink.looksLikeVideo(clip) {
                text = BiliLink.extract(from: clip)
            }
        }
    }

    private func submit() {
        guard !busy, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        busy = true
        error = nil
        Task {
            do {
                try await library.recognize(text, shazam: shazam)
                text = ""
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
