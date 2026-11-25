import Foundation
import Testing
@testable import SonglineCore

/// 一条后端真实返回的格式（字段和 backend/src/songline/models.py 一致）。
let backendJob = """
{"id":"6a1d06265a04","url":"https://www.bilibili.com/video/BV1yzud64E6B","options":{"shazam":true},
 "stage":"done","progress":1.0,"message":"完成","error":null,
 "video":{"bvid":"BV1yzud64E6B","aid":1,"title":"2026-08-10 直播回放","owner":"主播","cover":"https://i0.hdslb.com/x.jpg",
          "duration":7823,"page":1,"pages":[{"page":1,"cid":2,"title":"p1","duration":7823}],"description":""},
 "timeline":[
   {"start":0.0,"end":180.5,"song":{"title":"寂寞沙洲冷","artist":"周传雄","netease_id":123},"confidence":0.9,
    "sources":["lyrics","shazam"],"evidence":"…","alternatives":[]},
   {"start":200.0,"end":260.0,"song":null,"confidence":0.4,"sources":["lyrics"],"evidence":"","alternatives":[]}
 ],
 "created_at":1795500000.5,"updated_at":1795500100.0}
"""

@Test func decodesBackendJob() throws {
    let job = try SonglineJSON.decoder().decode(Job.self, from: Data(backendJob.utf8))
    #expect(job.stage == .done && job.isFinished)
    #expect(job.video?.coverURL?.host == "i0.hdslb.com")
    #expect(job.timeline[0].song?.neteaseId == 123)
    #expect(job.timeline[1].title == "未识别")
    #expect(job.tracks.map(\.title) == ["寂寞沙洲冷", "未识别"])
    #expect(job.tracks[0].albumTitle == "2026-08-10 直播回放")
}

@Test func unknownStageDoesNotBreakDecoding() throws {
    let json = backendJob.replacingOccurrences(of: "\"stage\":\"done\"", with: "\"stage\":\"polishing\"")
    let job = try SonglineJSON.decoder().decode(Job.self, from: Data(json.utf8))
    #expect(job.stage == .unknown && !job.isFinished)
}

func tracks(_ n: Int) -> [Track] {
    (0..<n).map { Track(jobID: "j", index: $0, start: Double($0) * 100, end: Double($0) * 100 + 60,
                        title: "歌\($0)", artist: "", albumTitle: "回放") }
}

@Test func queueAdvancesAndStopsAtTheEnd() {
    var q = TrackQueue(items: tracks(2), position: 0)
    #expect(q.advance()?.index == 1)
    #expect(q.advance() == nil)
    #expect(q.current?.index == 1)
}

@Test func previousRestartsUnlessJustStarted() {
    var q = TrackQueue(items: tracks(3), position: 1)
    #expect(q.back(elapsed: 10) == .restart(q.items[1]))
    #expect(q.back(elapsed: 1) == .previous(q.items[0]))
    #expect(q.back(elapsed: 1) == .restart(q.items[0]))  // 第一首：没有上一首了
}

@Test func outOfRangePositionMeansNothingPlaying() {
    #expect(TrackQueue(items: tracks(2), position: 5).current == nil)
}

@Test(arguments: [(0.0, "00:00"), (65, "01:05"), (3725, "1:02:05"), (-3, "00:00"), (.nan, "00:00")])
func formatsTime(seconds: Double, text: String) {
    #expect(formatTime(seconds) == text)
}

@Test func extractsLinkFromShareText() {
    let share = "【2026-11-24 直播回放-哔哩哔哩】 https://b23.tv/AbCdEf1 复制链接打开"
    #expect(BiliLink.extract(from: share) == "https://b23.tv/AbCdEf1")
    #expect(BiliLink.extract(from: "看看 BV1CK1FzMEU8 这个") == "BV1CK1FzMEU8")
    #expect(BiliLink.looksLikeVideo(share) && !BiliLink.looksLikeVideo("今天吃什么"))
}

@Test func timelineTextIsReadyToPaste() throws {
    let job = try SonglineJSON.decoder().decode(Job.self, from: Data(backendJob.utf8))
    #expect(job.timelineText == "2026-08-10 直播回放\n0:00:00 寂寞沙洲冷 - 周传雄\n0:03:20 未识别")
}
