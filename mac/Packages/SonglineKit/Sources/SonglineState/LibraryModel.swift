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

    public func rerun(_ job: Job) async throws {
        try await recognize(job.url, shazam: job.options.shazam)
    }

    public func cancel(_ job: Job) async {
        if let updated = try? await service.cancelJob(id: job.id) { upsert(updated) }
    }

    public func delete(_ job: Job) async throws {
        try await service.deleteJob(id: job.id)
        watchers.removeValue(forKey: job.id)?.cancel()
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
