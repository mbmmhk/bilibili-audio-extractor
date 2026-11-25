import Foundation
import Observation
import os
import SonglineCore

/// 收藏或播放过的一首歌。按「哪个 B 站视频的第几 P、从第几秒开始」记，
/// 不记任务 id：删掉识别记录再重新识别，收藏依然对得上。
public struct SavedSong: Codable, Sendable, Hashable, Identifiable {
    public var bvid: String
    public var page: Int
    public var start: Double
    public var end: Double
    public var title: String
    public var artist: String
    public var albumTitle: String
    public var coverURL: URL?
    public var date: Date

    /// 同一首歌（同一视频、同一段）的标识。开始时间取整，避免识别校正带来的零点几秒差异。
    public var id: String { "\(bvid)#\(page)#\(Int(start.rounded()))" }

    public init(track: Track, date: Date = Date()) {
        bvid = track.bvid ?? ""
        page = track.page
        start = track.start
        end = track.end
        title = track.title
        artist = track.artist
        albumTitle = track.albumTitle
        coverURL = track.coverURL
        self.date = date
    }

    public var duration: Double { max(0, end - start) }
}

/// 我喜欢的歌、最近播放。存在本机一个 JSON 文件里。
@MainActor @Observable
public final class LibraryStore {
    /// 最新收藏的在前。
    public private(set) var favorites: [SavedSong] = []
    /// 最近播放的在前，同一首只留最近一次。
    public private(set) var recent: [SavedSong] = []

    public static let recentLimit = 200

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let logger = Logger(subsystem: "app.songline", category: "store")

    private struct Contents: Codable {
        var favorites: [SavedSong] = []
        var recent: [SavedSong] = []
    }

    /// `file` 为 nil 时只存在内存里（预览、测试用）。
    public init(file: URL?) {
        self.file = file
        guard let file, let data = try? Data(contentsOf: file) else { return }
        do {
            let contents = try JSONDecoder().decode(Contents.self, from: data)
            favorites = contents.favorites
            recent = contents.recent
        } catch {
            logger.error("could not read \(file.path): \(error.localizedDescription)")
        }
    }

    /// 默认位置：~/Library/Application Support/Songline/library.json
    public static func standardFile() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Songline/library.json")
    }

    // MARK: - 我喜欢的歌

    public func isFavorite(_ track: Track) -> Bool {
        guard track.bvid != nil else { return false }
        let id = SavedSong(track: track).id
        return favorites.contains { $0.id == id }
    }

    /// 收藏 / 取消收藏。没有对应 B 站视频的歌（还在解析中）收藏不了，返回 false。
    @discardableResult
    public func toggleFavorite(_ track: Track) -> Bool {
        guard track.bvid != nil else { return false }
        let song = SavedSong(track: track)
        if let i = favorites.firstIndex(where: { $0.id == song.id }) {
            favorites.remove(at: i)
        } else {
            favorites.insert(song, at: 0)
        }
        save()
        return true
    }

    public func removeFavorite(id: SavedSong.ID) {
        favorites.removeAll { $0.id == id }
        save()
    }

    // MARK: - 最近播放

    public func recordPlay(_ track: Track, at date: Date = Date()) {
        guard track.bvid != nil else { return }
        let song = SavedSong(track: track, date: date)
        recent.removeAll { $0.id == song.id }
        recent.insert(song, at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
        save()
    }

    public func clearRecent() {
        recent.removeAll()
        save()
    }

    // MARK: - 内部

    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Contents(favorites: favorites, recent: recent)).write(to: file, options: .atomic)
        } catch {
            logger.error("could not save \(file.path): \(error.localizedDescription)")
        }
    }
}
