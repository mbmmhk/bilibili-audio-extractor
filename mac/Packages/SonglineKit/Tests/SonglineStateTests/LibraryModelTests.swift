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
