import Foundation

public struct FileState: Codable, Sendable, Equatable {
    public var size: UInt64
    public var mtime: Date
    /// Offset em bytes até onde o arquivo já foi parseado.
    public var byteOffset: UInt64

    public init(size: UInt64, mtime: Date, byteOffset: UInt64) {
        self.size = size
        self.mtime = mtime
        self.byteOffset = byteOffset
    }
}

/// Estado de leitura por arquivo, para que só o delta seja reparseado.
public struct ParseCache: Codable, Sendable, Equatable {
    public var files: [String: FileState]

    public init(files: [String: FileState] = [:]) {
        self.files = files
    }

    public static func load(from url: URL) -> ParseCache {
        // Cache corrompido ou ausente não é erro: descarta e reparseia tudo.
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(ParseCache.self, from: data)
        else { return ParseCache() }
        return cache
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// `~/Library/Application Support/ClaudeTokenCounter/cache.json`
    public static var defaultURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/ClaudeTokenCounter/cache.json")
    }
}
