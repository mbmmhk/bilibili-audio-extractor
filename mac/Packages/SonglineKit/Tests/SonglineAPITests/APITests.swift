import Foundation
import Testing
@testable import SonglineAPI

@Test func parsesServerSentEventLines() throws {
    let line = #"data: {"id":"a","url":"u","options":{"shazam":true},"stage":"transcribing","progress":0.5,"message":"识别歌词","error":null,"video":null,"timeline":[],"created_at":1,"updated_at":2}"#
    let job = try #require(try HTTPSonglineService.parseEvent(line))
    #expect(job.stage == .transcribing && job.progress == 0.5)
    #expect(try HTTPSonglineService.parseEvent("") == nil)
    #expect(try HTTPSonglineService.parseEvent(": keep-alive") == nil)
}

@Test func errorsCarryTheBackendsMessage() throws {
    let response = HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
    #expect(throws: SonglineAPIError.http(status: 404, detail: "任务不存在")) {
        try HTTPSonglineService.check(response, body: Data(#"{"detail":"任务不存在"}"#.utf8))
    }
    let ok = HTTPURLResponse(url: URL(string: "http://x")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
    try HTTPSonglineService.check(ok, body: nil)
}

@Test func audioURLPointsAtTheBackend() {
    let api = HTTPSonglineService(baseURL: URL(string: "http://127.0.0.1:8765")!)
    #expect(api.audioURL(id: "abc").absoluteString == "http://127.0.0.1:8765/api/jobs/abc/audio")
}

@Test func mockHasDataForPreviews() async throws {
    let jobs = try await MockSonglineService().jobs()
    #expect(jobs.contains { $0.stage == .done } && jobs.contains { !$0.isFinished } && jobs.contains { $0.stage == .failed })
}
