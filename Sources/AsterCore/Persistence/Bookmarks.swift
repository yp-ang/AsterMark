import Foundation

/// Security-scoped bookmarks let the sandboxed app reopen folders the user chose in earlier sessions.
public enum Bookmarks {
    public struct Resolved: Sendable, Hashable {
        public let url: URL
        public let isStale: Bool
        /// A fresh bookmark to store in place of a stale one.
        public let refreshedData: Data?
    }

    public static func create(for url: URL, securityScoped: Bool = true) throws -> Data {
        try url.bookmarkData(
            options: securityScoped ? [.withSecurityScope] : [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public static func resolve(_ data: Data, securityScoped: Bool = true) throws -> Resolved {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: securityScoped ? [.withSecurityScope, .withoutUI] : [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        var refreshed: Data?
        if isStale {
            refreshed = withAccess(to: url) { try? create(for: url, securityScoped: securityScoped) }
        }
        return Resolved(url: url, isStale: isStale, refreshedData: refreshed)
    }

    /// Runs `body` with access to a security-scoped URL, balancing start/stop.
    /// Works for URLs that aren't security-scoped too (the start call just returns false).
    public static func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started { url.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }
}
