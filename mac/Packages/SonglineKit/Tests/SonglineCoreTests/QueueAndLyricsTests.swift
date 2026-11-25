import Foundation
import Testing
@testable import SonglineCore

/// 同一场回放里的几首歌：0–60、100–160、200–260 …
func songs(_ n: Int, job: String = "j") -> [Track] {
    (0..<n).map { Track(jobID: job, index: $0, start: Double($0) * 100, end: Double($0) * 100 + 60,
                        title: "歌\($0)", artist: "", albumTitle: "回放") }
}

// MARK: - 编辑队列

@Test func insertNextGoesRightAfterTheCurrentSong() {
    var q = TrackQueue(items: songs(3), position: 0)
    let extra = songs(1, job: "k")
    q.insertNext(extra)
    #expect(q.items.map(\.id) == ["j#0", "k#0", "j#1", "j#2"])
    #expect(q.next?.id == "k#0")
}

@Test func removingSongsKeepsTheCurrentOne() {
    var q = TrackQueue(items: songs(4), position: 2)
    let removedCurrent = q.remove(at: 2)  // 正在播放的不能删
    let removedFirst = q.remove(at: 0)
    #expect(!removedCurrent && removedFirst)
    #expect(q.current?.id == "j#2" && q.position == 1)
    let removedLast = q.remove(at: 2)
    #expect(removedLast)
    #expect(q.items.map(\.id) == ["j#1", "j#2"])
}

@Test func movingSongsFollowsTheCurrentOne() {
    var q = TrackQueue(items: songs(4), position: 1)
    q.move(from: 1, to: 3)
    #expect(q.items.map(\.id) == ["j#0", "j#2", "j#3", "j#1"])
    #expect(q.current?.id == "j#1" && q.position == 3)
    q.move(from: 0, to: 2)
    #expect(q.current?.id == "j#1")
}

@Test func jumpAndClearUpcoming() {
    var q = TrackQueue(items: songs(4), position: 0)
    let jumped = q.jump(to: 2)
    #expect(jumped?.id == "j#2")
    #expect(q.upcoming.map(\.id) == ["j#3"])
    q.clearUpcoming()
    #expect(q.items.map(\.id) == ["j#2"] && q.position == 0)
}

// MARK: - 只听歌 / 整场

@Test func songsOnlyJumpsOverChat() {
    let q = TrackQueue(items: songs(2), position: 0)
    #expect(TickAction.at(time: 30, queue: q, mode: .songsOnly) == .none)
    #expect(TickAction.at(time: 60, queue: q, mode: .songsOnly) == .jumpToNext)
    let last = TrackQueue(items: songs(2), position: 1)
    #expect(TickAction.at(time: 160, queue: last, mode: .songsOnly) == .stop)
}

@Test func wholeStreamPlaysThroughChat() {
    let q = TrackQueue(items: songs(2), position: 0)
    #expect(TickAction.at(time: 80, queue: q, mode: .wholeStream) == .none)      // 聊天中，继续播
    #expect(TickAction.at(time: 100, queue: q, mode: .wholeStream) == .enteredNext)
    let last = TrackQueue(items: songs(2), position: 1)
    #expect(TickAction.at(time: 500, queue: last, mode: .wholeStream) == .none)  // 最后一首后也继续播到结尾
}

@Test func wholeStreamStillJumpsToAnotherStream() {
    let q = TrackQueue(items: songs(1) + songs(1, job: "k"), position: 0)
    #expect(TickAction.at(time: 30, queue: q, mode: .wholeStream) == .none)
    #expect(TickAction.at(time: 60, queue: q, mode: .wholeStream) == .jumpToNext)
}

// MARK: - 歌词

let sampleLyrics = Lyrics(segments: [
    Segment(start: 10, end: 14, text: "第二句"),
    Segment(start: 5, end: 9, text: "第一句"),
    Segment(start: 15, end: 18, text: " "),
    Segment(start: 70, end: 74, text: "聊天"),
])

@Test func lyricsAreSortedAndBlankLinesDropped() {
    #expect(sampleLyrics.lines.map(\.text) == ["第一句", "第二句", "聊天"])
}

@Test func lyricsForATrackAndTheCurrentLine() {
    let track = songs(1)[0]  // 0–60
    let lines = sampleLyrics.lines(for: track)
    #expect(lines.map(\.text) == ["第一句", "第二句"])
    #expect(sampleLyrics.index(at: 3, in: lines) == nil)
    #expect(sampleLyrics.index(at: 5, in: lines) == 0)
    #expect(sampleLyrics.index(at: 12, in: lines) == 1)
    #expect(sampleLyrics.index(at: 50, in: lines) == 1)
}

// MARK: - 链接

@Test func readsVideoAndPageFromLinks() {
    #expect(BiliLink.video(in: "https://www.bilibili.com/video/BV1CK1FzMEU8/?p=3&spm=1")! == ("BV1CK1FzMEU8", 3))
    #expect(BiliLink.video(in: "BV1CK1FzMEU8")! == ("BV1CK1FzMEU8", 1))
    #expect(BiliLink.video(in: "https://b23.tv/AbCdEf1") == nil)
}

@Test func tracksCarryTheirVideo() throws {
    let job = try SonglineJSON.decoder().decode(Job.self, from: Data(backendJob.utf8))
    #expect(job.tracks[0].bvid == "BV1yzud64E6B" && job.tracks[0].page == 1)
    #expect(job.isVideo(bvid: "BV1yzud64E6B", page: 1) && !job.isVideo(bvid: "BV1yzud64E6B", page: 2))
}
