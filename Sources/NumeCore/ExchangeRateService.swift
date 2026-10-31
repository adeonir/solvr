import Foundation
import Observation

@MainActor
public protocol ExchangeRateCache {
    func load() throws -> ExchangeRateSnapshot?
    func save(_ snapshot: ExchangeRateSnapshot) throws
}

public struct FileExchangeRateCache: ExchangeRateCache {
    public let url: URL
    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> ExchangeRateSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(ExchangeRateSnapshot.self, from: Data(contentsOf: url))
    }

    public func save(_ snapshot: ExchangeRateSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}

@MainActor
@Observable
public final class ExchangeRateService {
    public private(set) var snapshot: ExchangeRateSnapshot = .shipped
    public private(set) var isUpdating = false
    public private(set) var lastUpdateFailed = false
    public private(set) var isForeground = false
    @ObservationIgnored private let source: any ExchangeRateSource
    @ObservationIgnored private let cache: any ExchangeRateCache
    @ObservationIgnored private var hasAttempted = false
    @ObservationIgnored private var lastAttempt: Date?

    public init(source: any ExchangeRateSource, cache: any ExchangeRateCache) {
        self.source = source
        self.cache = cache
        if let cached = try? cache.load(),
           (try? ExchangeRateTable(base: cached.base, rates: cached.rates).validate()) != nil,
           cached.fetchedAt.timeIntervalSince1970.isFinite
        {
            snapshot = cached
        }
    }

    /// Next foreground attempt. Failures keep the old snapshot but do not
    /// cause a tight retry loop; returning to the app rechecks its age.
    public var nextRefreshDate: Date? {
        guard isForeground else { return nil }
        return lastAttempt?.addingTimeInterval(1800)
    }

    public func setForeground(_ foreground: Bool, now: Date) async {
        let returning = foreground && !isForeground
        isForeground = foreground
        guard foreground else { return }
        if returning, now.timeIntervalSince(snapshot.fetchedAt) >= 1800 {
            lastAttempt = nil
        }
        await refreshIfDue(now: now)
    }

    public func refreshIfDue(now: Date) async {
        guard isForeground, !isUpdating, !hasAttempted || lastAttempt == nil || now.timeIntervalSince(lastAttempt!) >= 1800 else { return }
        hasAttempted = true
        lastAttempt = now
        isUpdating = true
        defer { isUpdating = false }
        do {
            let table = try await source.fetch()
            try table.validate()
            let fresh = ExchangeRateSnapshot(base: table.base, rates: table.rates, fetchedAt: now)
            // Publish only once the replacement is durable. Neither network
            // nor disk failure can discard the last usable snapshot.
            try cache.save(fresh)
            snapshot = fresh
            lastUpdateFailed = false
        } catch {
            lastUpdateFailed = true
        }
    }
}
