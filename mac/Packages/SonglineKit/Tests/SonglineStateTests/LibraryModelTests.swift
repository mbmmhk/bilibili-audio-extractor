import Foundation
import Testing
import SonglineAPI
import SonglineCore
@testable import SonglineState

@MainActor
@Test func refreshLoadsJobsNewestFirst() async {
    let library = LibraryModel(service: MockSonglineService())
    await library.refresh()
    #expect(library.jobs.map(\.id) == MockSonglineService.samples.map(\.id))
    #expect(library.loadError == nil)
}

@MainActor
@Test func recognizeAddsTheJobAndSelectsIt() async throws {
    let library = LibraryModel(service: MockSonglineService(jobs: []))
    try await library.recognize("分享 https://b23.tv/AbCdEf1 打开", shazam: false)
    let job = try #require(library.jobs.first)
    #expect(job.url == "https://b23.tv/AbCdEf1" && job.options.shazam == false)
    #expect(library.selection == .job(job.id))
}

@MainActor
@Test func deletingTheSelectedJobGoesBackToRecognize() async throws {
    let library = LibraryModel(service: MockSonglineService())
    await library.refresh()
    let job = try #require(library.job("demo-1119"))
    library.selection = .job(job.id)
    try await library.delete(job)
    #expect(library.job("demo-1119") == nil)
    #expect(library.selection == .recognize)
}

@MainActor
@Test func previewModelIsReadyWithoutABackend() {
    let model = SonglineAppModel(previewing: MockSonglineService())
    #expect(model.library != nil && model.player != nil)
}

// MARK: - 第 2 步：打开链接、歌词、收藏

@MainActor
@Test func openingARecognisedVideoSelectsItInsteadOfRerunning() async throws {
    let library = LibraryModel(service: MockSonglineService())
    await library.refresh()
    let opened = try await library.open("https://www.bilibili.com/video/BV1s6sa6aExh/?spm_id_from=333")
    #expect(opened.id == "demo-1119")
    #expect(library.jobs.count == MockSonglineService.samples.count)  // 没有新建任务
}

@MainActor
@Test func openingANewVideoStartsRecognising() async throws {
    let library = LibraryModel(service: MockSonglineService())
    await library.refresh()
    let opened = try await library.open("https://www.bilibili.com/video/BV1NewVideo01")
    #expect(opened.stage == .queued && library.selection == .job(opened.id))
}

@MainActor
@Test func lyricsComeFromTheTranscript() async throws {
    let library = LibraryModel(service: MockSonglineService())
    await library.refresh()
    let lyrics = try await library.lyrics(for: "demo-1119")
    #expect(lyrics.lines.first?.text == "今夜的风悄悄月悄悄")
}

@Test func readsVideoLinksFromURLs() {
    let wrapped = URL(string: "songline://open?url=https%3A%2F%2Fwww.bilibili.com%2Fvideo%2FBV1CK1FzMEU8%2F%3Fp%3D2")!
    #expect(SonglineAppModel.videoLink(in: wrapped) == "https://www.bilibili.com/video/BV1CK1FzMEU8/?p=2")
    #expect(SonglineAppModel.videoLink(in: URL(string: "https://www.bilibili.com/video/BV1CK1FzMEU8")!) != nil)
    #expect(SonglineAppModel.videoLink(in: URL(string: "songline://open?url=https%3A%2F%2Fexample.com")!) == nil)
    #expect(SonglineAppModel.videoLink(in: URL(string: "https://example.com/a")!) == nil)
}

@MainActor
@Test func savedSongsMapBackToPlayableTracks() async throws {
    let model = SonglineAppModel(previewing: MockSonglineService())
    await model.library?.refresh()
    let job = try #require(model.library?.job("demo-1119"))
    var song = job.tracks[1]
    song.start += 4  // 重新识别后时间略有出入
    model.store.toggleFavorite(song)
    let tracks = model.tracks(for: model.store.favorites)
    #expect(tracks.map(\.id) == [job.tracks[1].id])
}

@MainActor
@Test func playingASongRecordsItAsRecent() async throws {
    let model = SonglineAppModel(previewing: MockSonglineService())
    await model.library?.refresh()
    let job = try #require(model.library?.job("demo-1119"))
    model.player?.play(job.tracks, startAt: 2)
    #expect(model.store.recent.first?.title == job.tracks[2].title)
}

// MARK: - 搜索、自动刷新

/// 记录会在「别处」改变的假服务：模拟在网页版里删掉了一条。
final class ChangingService: SonglineService, @unchecked Sendable {
    private let lock = NSLock()
    private var current = MockSonglineService.samples
    func remove(_ id: String) { lock.lock(); current.removeAll { $0.id == id }; lock.unlock() }
    private var mock: MockSonglineService { lock.lock(); defer { lock.unlock() }; return MockSonglineService(jobs: current) }
    func jobs() async throws -> [Job] { try await mock.jobs() }
    func job(id: String) async throws -> Job { try await mock.job(id: id) }
    func createJob(url: String, shazam: Bool) async throws -> Job { try await mock.createJob(url: url, shazam: shazam) }
    func cancelJob(id: String) async throws -> Job { try await mock.cancelJob(id: id) }
    func deleteJob(id: String) async throws {}
    func transcript(id: String) async throws -> [Segment] { [] }
    func events(id: String) -> AsyncThrowingStream<Job, Error> { mock.events(id: id) }
    func audioURL(id: String) -> URL { mock.audioURL(id: id) }
}

@MainActor
@Test func refreshPicksUpChangesMadeElsewhere() async {
    let service = ChangingService()
    let library = LibraryModel(service: service)
    await library.refresh()
    library.selection = .job("demo-1119")
    service.remove("demo-1119")
    await library.refresh()
    #expect(library.job("demo-1119") == nil)
    #expect(library.selection == .recognize)
}

@MainActor
@Test func becomingActiveRefreshesAtMostEveryFewSeconds() async throws {
    let service = ChangingService()
    let model = SonglineAppModel(previewing: service)
    await model.library?.refresh()
    service.remove("demo-1119")
    let t0 = Date()
    model.appDidBecomeActive(now: t0)
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.library?.job("demo-1119") == nil)
    // 2 秒内再次切回：不刷新。
    service.remove("demo-failed")
    model.appDidBecomeActive(now: t0.addingTimeInterval(2))
    try await Task.sleep(for: .milliseconds(100))
    #expect(model.library?.job("demo-failed") != nil)
}

@MainActor
@Test func searchGoesThroughTheLibrary() async {
    let library = LibraryModel(service: MockSonglineService())
    await library.refresh()
    #expect(library.search("孙燕姿").tracks.map(\.title) == ["遇见"])
}
