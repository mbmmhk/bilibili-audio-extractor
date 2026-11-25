import SonglineCore
import SonglineState
import SwiftUI

struct SidebarView: View {
    @Bindable var library: LibraryModel
    @State private var deleting: Job?

    var body: some View {
        List(selection: $library.selection) {
            Label("识别新回放", systemImage: "plus.circle")
                .tag(LibraryModel.Selection.recognize)

            Section("回放歌单") {
                ForEach(library.jobs) { job in
                    JobRow(job: job)
                        .tag(LibraryModel.Selection.job(job.id))
                        .contextMenu {
                            Button("删除…", role: .destructive) { deleting = job }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay(alignment: .bottom) {
            if let error = library.loadError {
                Text(error).font(.caption).foregroundStyle(.red).padding(8)
            }
        }
        .confirmationDialog(
            "删除「\(deleting?.title ?? "")」？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("删除", role: .destructive) {
                if let job = deleting { Task { try? await library.delete(job) } }
            }
        } message: {
            Text("只删除识别记录，不影响 B 站上的视频。")
        }
    }
}

struct JobRow: View {
    var job: Job

    var body: some View {
        HStack(spacing: 10) {
            CoverImage(url: job.video?.coverURL, size: 38, corner: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(job.stage == .failed ? .red : .secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        switch job.stage {
        case .done: "\(job.timeline.count) 首"
        case .failed: "识别失败"
        case .cancelled: "已取消"
        default: "识别中 \(Int(job.progress * 100))%"
        }
    }
}
