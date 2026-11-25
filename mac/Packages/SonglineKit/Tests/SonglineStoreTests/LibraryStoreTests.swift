import Foundation
import Testing
import SonglineCore
@testable import SonglineStore

func track(_ i: Int, job: String = "j", bvid: String? = "BV1CK1FzMEU8") -> Track {
    Track(jobID: job, index: i, start: Double(i) * 100, end: Double(i) * 100 + 60, title: "歌\(i)", artist: "某人",
          albumTitle: "回放", bvid: bvid)
}

@MainActor
@Test func favoritesToggleAndSurviveReidentification() {
    let store = LibraryStore(file: nil)
    #expect(store.toggleFavorite(track(1)))
    #expect(store.isFavorite(track(1)))
    // 删掉记录重新识别后 jobID 变了，开始时间也有零点几秒的差异：仍然算同一首。
    var again = track(1, job: "new-job")
    again.start += 0.3
    #expect(store.isFavorite(again))
    store.toggleFavorite(again)
    #expect(store.favorites.isEmpty)
}

@MainActor
@Test func songsWithoutAVideoCannotBeSaved() {
    let store = LibraryStore(file: nil)
    #expect(!store.toggleFavorite(track(1, bvid: nil)))
    store.recordPlay(track(1, bvid: nil))
    #expect(store.favorites.isEmpty && store.recent.isEmpty)
}

@MainActor
@Test func recentKeepsTheLatestPlayOfEachSong() {
    let store = LibraryStore(file: nil)
    store.recordPlay(track(1), at: Date(timeIntervalSince1970: 1))
    store.recordPlay(track(2), at: Date(timeIntervalSince1970: 2))
    store.recordPlay(track(1), at: Date(timeIntervalSince1970: 3))
    #expect(store.recent.map(\.title) == ["歌1", "歌2"])
    for i in 0..<(LibraryStore.recentLimit + 5) { store.recordPlay(track(i)) }
    #expect(store.recent.count == LibraryStore.recentLimit)
}

@MainActor
@Test func savesToDiskAndLoadsBack() throws {
    let file = FileManager.default.temporaryDirectory.appending(path: "songline-\(UUID().uuidString)/library.json")
    let store = LibraryStore(file: file)
    store.toggleFavorite(track(1))
    store.recordPlay(track(2))
    let reloaded = LibraryStore(file: file)
    #expect(reloaded.favorites.map(\.title) == ["歌1"])
    #expect(reloaded.recent.map(\.title) == ["歌2"])
}
