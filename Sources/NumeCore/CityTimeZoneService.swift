// CityTimeZoneService (ADK-250): owns the city data cache and asks the
// external source for the cities a sheet could not resolve. A lookup that
// succeeds replaces the cached entry and publishes the fresh cache; a
// lookup that fails leaves the cache untouched, so a city resolved before
// keeps converting without a connection (NFR-2).

import Foundation
import Observation

@MainActor
public protocol CityTimeZoneCache {
    func load() throws -> CityTimeZoneSnapshot?
    func save(_ snapshot: CityTimeZoneSnapshot) throws
}

public struct FileCityTimeZoneCache: CityTimeZoneCache {
    public let url: URL
    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> CityTimeZoneSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(CityTimeZoneSnapshot.self, from: Data(contentsOf: url))
    }

    public func save(_ snapshot: CityTimeZoneSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}

@MainActor
@Observable
public final class CityTimeZoneService {
    /// The city data the sheets evaluate against.
    public private(set) var snapshot: CityTimeZoneSnapshot
    public private(set) var isUpdating = false
    public private(set) var lastUpdateFailed = false
    @ObservationIgnored private let source: any CityTimeZoneSource
    @ObservationIgnored private let cache: any CityTimeZoneCache
    @ObservationIgnored private var attempts: [String: Date] = [:]
    /// The cities asked for while a lookup was already running; the running
    /// lookup takes them before it publishes, so no city is dropped.
    @ObservationIgnored private var pending: Set<String> = []

    public init(source: any CityTimeZoneSource, cache: any CityTimeZoneCache) {
        self.source = source
        self.cache = cache
        snapshot = (try? cache.load()) ?? .empty
    }

    /// Keeps the city data current for the cities the visible results name,
    /// then publishes the cache. A city already in the cache is looked up
    /// again, so a successful fetch replaces its entry; the cached entry
    /// keeps converting only while the source is unreachable or a fetch
    /// fails (NFR-2). A city asked for during a running lookup joins that
    /// lookup instead of being dropped. A retry waits for the recheck
    /// interval, so a sheet that keeps changing its text does not keep
    /// asking.
    public func resolve(_ cities: Set<String>, now: Date) async {
        pending.formUnion(cities)
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        while !pending.isEmpty {
            let batch = pending.sorted()
            pending.removeAll()
            var resolved = snapshot
            var failed = false
            for city in batch {
                guard !isRecentlyAttempted(city, now: now) else { continue }
                let query = CityTimeZones.expanded(city)
                attempts[CityTimeZones.folded(query)] = now
                do {
                    let records = try await source.lookup(query)
                    resolved = resolved.recording(
                        CityTimeZones.outcome(for: query, records: records), for: query
                    )
                } catch {
                    failed = true
                }
            }
            lastUpdateFailed = failed
            // Publish only once the replacement is durable: neither network nor
            // disk failure can discard the last usable city data.
            guard resolved != snapshot, (try? cache.save(resolved)) != nil else { continue }
            snapshot = resolved
        }
    }

    /// How often a city the source did not resolve is asked for again.
    static let recheckInterval: TimeInterval = 1800

    private func isRecentlyAttempted(_ city: String, now: Date) -> Bool {
        guard let attempt = attempts[CityTimeZones.key(city)] else { return false }
        return now.timeIntervalSince(attempt) < Self.recheckInterval
    }
}
