import Foundation
import Testing
@testable import SonglineCore

let searchJobs: [Job] = [
    Job(id: "new", url: "u", stage: .done,
        video: VideoInfo(bvid: "BV1", title: "11-24 直播回放", owner: "一口甜", duration: 100),
        timeline: [
            TimelineEntry(start: 0, end: 10, song: SongRef(title: "Love Story", artist: "Taylor Swift")),
            TimelineEntry(start: 20, end: 30, song: SongRef(title: "小星星", artist: "汪苏泷")),
            TimelineEntry(start: 40, end: 50, song: nil),
        ], createdAt: 2),
    Job(id: "old", url: "u", stage: .done,
        video: VideoInfo(bvid: "BV2", title: "11-13 直播回放", owner: "一口甜", duration: 100),
        timeline: [
            TimelineEntry(start: 0, end: 10, song: SongRef(title: "万有引力", artist: "汪苏泷")),
            TimelineEntry(start: 20, end: 30, song: SongRef(title: "汪汪队", artist: "某人")),
        ], createdAt: 1),
]

@Test func findsSongsByTitleOrArtistIgnoringCaseAndWidth() {
    #expect(Search.run("ＬＯＶＥ story", in: searchJobs).tracks.map(\.title) == ["Love Story"])
    #expect(Search.run("汪苏泷", in: searchJobs).tracks.map(\.title) == ["小星星", "万有引力"])
}

@Test func titleMatchesComeFirst() {
    // 「汪」：「汪汪队」歌名就匹配，排在只有原唱匹配的前面。
    #expect(Search.run("汪", in: searchJobs).tracks.map(\.title) == ["汪汪队", "小星星", "万有引力"])
}

@Test func everyWordMustMatch() {
    #expect(Search.run("汪苏泷 11-13", in: searchJobs).tracks.map(\.title) == ["万有引力"])
    #expect(Search.run("汪苏泷 不存在", in: searchJobs).isEmpty)
}

@Test func findsPlaylistsAndSkipsUnidentifiedSongs() {
    let r = Search.run("一口甜 11-24", in: searchJobs)
    #expect(r.jobs.map(\.id) == ["new"])
    #expect(Search.run("未识别", in: searchJobs).tracks.isEmpty)
    #expect(Search.run("   ", in: searchJobs).isEmpty)
}
