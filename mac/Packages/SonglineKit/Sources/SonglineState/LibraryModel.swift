import Foundation
import Observation
import SonglineAPI
import SonglineCore

/// 资料库：所有直播回放（歌单），以及侧边栏当前选中了什么。
@MainActor @Observable
public final class LibraryModel {
    public enum Selection: Hashable {
        case recognize
        case job(String)
    }

    public private(set) var jobs: [Job] = []
    public var selection: Selection? = .recognize
    public private(set) var loadError: String?

    public let service: any SonglineService
    /// 正在跟踪实时进度的任务。
    @ObservationIgnored private var watchers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lyricsCache: [String: Lyrics] = [:]

    public init(service: any SonglineService) {
        self.service = service
    }

    public func job(_ id: String) -> Job? { jobs.first { $0.id == id } }

    public func refresh() async {
        do {
            jobs = try await service.jobs()
            loadError = nil
            jobs.filter { !$0.isFinished }.forEach(watch)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 识别一个新视频。`text` 可以是链接、BV 号或分享文字。
    public func recognize(_ text: String, shazam: Bool) async throws {
        let job = try await service.createJob(url: BiliLink.extract(from: text), shazam: shazam)
        upsert(job)
        selection = .job(job.id)
        watch(job)
    }

    /// 打开一个 B 站视频：已经识别完的直接选中它，没有的才新建识别。
    /// 返回打开的那条记录。（「发送到 Songline」、拖进来的链接、`songline://` 都走这里。）
    @discardableResult
    public func open(_ text: String, shazam: Bool = true) async throws -> Job {
        if let (bvid, page) = BiliLink.video(in: text),
           let done = jobs.first(where: { $0.stage == .done && $0.isVideo(bvid: bvid, page: page) }) {
            selection = .job(done.id)
            return done
        }
        try await recognize(text, shazam: shazam)
        guard case let .job(id) = selection, let job = job(id) else { throw CancellationError() }
        return job
    }

    /// 一场回放的歌词（语音转写）。识别完的会缓存；识别中的每次重新取，因为还在增加。
    public func lyrics(for jobID: String) async throws -> Lyrics {
        if let cached = lyricsCache[jobID] { return cached }
        let lyrics = Lyrics(segments: try await service.transcript(id: jobID))
        if job(jobID)?.stage == .done { lyricsCache[jobID] = lyrics }
        return lyrics
    }

    public func rerun(_ job: Job) async throws {
        try await recognize(job.url, shazam: job.options.shazam)
    }

    public func cancel(_ job: Job) async {
        if let updated = try? await service.cancelJob(id: job.id) { upsert(updated) }
    }

    public func delete(_ job: Job) async throws {
        try await service.deleteJob(id: job.id)
        watchers.removeValue(forKey: job.id)?.cancel()
        lyricsCache[job.id] = nil
        jobs.removeAll { $0.id == job.id }
        if selection == .job(job.id) { selection = .recognize }
    }

    // MARK: - 实时进度

    private func watch(_ job: Job) {
        guard watchers[job.id] == nil, !job.isFinished else { return }
        let id = job.id
        let service = self.service
        watchers[id] = Task { [weak self] in
            // 连接断了就隔几秒重连，直到任务结束。
            while !Task.isCancelled {
                do {
                    for try await update in service.events(id: id) { self?.upsert(update) }
                } catch {}
                guard let latest = try? await service.job(id: id) else { break }
                self?.upsert(latest)
                if latest.isFinished { break }
                try? await Task.sleep(for: .seconds(2))
            }
            self?.watchers[id] = nil
        }
    }

    private func upsert(_ job: Job) {
        if let i = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[i] = job
        } else {
            jobs.insert(job, at: 0)
        }
    }
}
