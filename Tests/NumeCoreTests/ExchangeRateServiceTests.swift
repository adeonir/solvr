import Foundation
@testable import NumeCore
import Testing

@MainActor
struct ExchangeRateServiceTests {
    private let instant = Date(timeIntervalSince1970: 10000)

    @Test func shippedRatesRemainUsableUntilFirstSuccessfulFetch() async {
        let source = ControlledRateSource()
        let service = ExchangeRateService(source: source, cache: MemoryRateCache())
        #expect(service.snapshot == .shipped)
        await source.enqueue(.failure(.invalidResponse))
        await service.setForeground(true, now: instant)
        #expect(service.snapshot == .shipped)
        #expect(service.lastUpdateFailed)
    }

    @Test func foregroundCadenceAndReturnUseThirtyMinutesAndNeverFetchInBackground() async {
        let source = ControlledRateSource()
        let service = ExchangeRateService(source: source, cache: MemoryRateCache())
        await service.refreshIfDue(now: instant)
        #expect(await source.calls == 0)
        await service.setForeground(true, now: instant)
        #expect(await source.calls == 1)
        #expect(service.snapshot.fetchedAt == instant)
        await service.refreshIfDue(now: instant.addingTimeInterval(1799))
        #expect(await source.calls == 1)
        await service.refreshIfDue(now: instant.addingTimeInterval(1800))
        #expect(await source.calls == 2)
        await service.setForeground(false, now: instant.addingTimeInterval(1801))
        await service.refreshIfDue(now: instant.addingTimeInterval(7200))
        #expect(await source.calls == 2)
        await service.setForeground(true, now: instant.addingTimeInterval(7200))
        #expect(await source.calls == 3)
        await service.setForeground(false, now: instant.addingTimeInterval(7201))
        await service.setForeground(true, now: instant.addingTimeInterval(7202))
        #expect(await source.calls == 3)
    }

    @Test func failedUpdateLeavesPersistentCacheUnchangedAndRestartUsesItRegardlessOfAge() async throws {
        let cache = MemoryRateCache()
        let source = ControlledRateSource()
        let service = ExchangeRateService(source: source, cache: cache)
        await service.setForeground(true, now: instant)
        let saved = service.snapshot
        #expect(saved.rates["BRL"] == 5)
        await source.enqueue(.failure(.invalidResponse))
        await service.refreshIfDue(now: instant.addingTimeInterval(1800))
        #expect(service.snapshot == saved)
        #expect(try cache.load() == saved)
        #expect(service.lastUpdateFailed)
        let restarted = ExchangeRateService(source: source, cache: cache)
        #expect(restarted.snapshot == saved)
        await restarted.setForeground(false, now: instant.addingTimeInterval(1_000_000))
        #expect(restarted.snapshot == saved)
    }

    @Test func inFlightUpdateUsesCachedRatesAndDeduplicatesOtherRequests() async {
        let source = ControlledRateSource()
        let cache = MemoryRateCache(snapshot: ExchangeRateSnapshot(base: "USD", rates: ["BRL": 5], fetchedAt: instant))
        let service = ExchangeRateService(source: source, cache: cache)
        await source.suspendNext()
        let refresh = Task { await service.setForeground(true, now: instant.addingTimeInterval(1800)) }
        await source.waitUntilSuspended()
        #expect(service.isUpdating)
        #expect(service.snapshot.rates["BRL"] == 5)
        await service.refreshIfDue(now: instant.addingTimeInterval(3600))
        #expect(await source.calls == 1)
        await source.resume(with: ExchangeRateTable(base: "EUR", rates: ["USD": 2, "BRL": 12]))
        await refresh.value
        #expect(service.snapshot.base == "EUR")
        #expect(service.snapshot.rates["BRL"] == 12)
        #expect(!service.isUpdating)
    }

    @Test func corruptOrInvalidCacheFallsBackToShippedRates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = FileExchangeRateCache(url: folder.appendingPathComponent("rates.json"))
        try Data("broken".utf8).write(to: cache.url)
        #expect(ExchangeRateService(source: ControlledRateSource(), cache: cache).snapshot == .shipped)
        try cache.save(ExchangeRateSnapshot(base: "USD", rates: ["BRL": -5], fetchedAt: instant))
        #expect(ExchangeRateService(source: ControlledRateSource(), cache: cache).snapshot == .shipped)
    }

    @Test func diskCacheSurvivesReopening() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("rates.json")
        let snapshot = ExchangeRateSnapshot(base: "EUR", rates: ["USD": 2, "BRL": 10], fetchedAt: instant)
        try FileExchangeRateCache(url: url).save(snapshot)
        #expect(try FileExchangeRateCache(url: url).load() == snapshot)
    }
}

@MainActor
private final class MemoryRateCache: ExchangeRateCache {
    var snapshot: ExchangeRateSnapshot?
    init(snapshot: ExchangeRateSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() throws -> ExchangeRateSnapshot? {
        snapshot
    }

    func save(_ snapshot: ExchangeRateSnapshot) throws {
        self.snapshot = snapshot
    }
}

private actor ControlledRateSource: ExchangeRateSource {
    var calls = 0
    private var queue: [Result<ExchangeRateTable, ExchangeRateUpdateError>] = []
    private var shouldSuspend = false
    private var continuation: CheckedContinuation<ExchangeRateTable, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func enqueue(_ response: Result<ExchangeRateTable, ExchangeRateUpdateError>) {
        queue.append(response)
    }

    func suspendNext() {
        shouldSuspend = true
    }

    func waitUntilSuspended() async {
        if continuation != nil {
            return
        }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume(with table: ExchangeRateTable) {
        continuation?.resume(returning: table); continuation = nil
    }

    func fetch() async throws -> ExchangeRateTable {
        calls += 1
        if shouldSuspend {
            shouldSuspend = false
            return await withCheckedContinuation {
                continuation = $0
                waiter?.resume()
                waiter = nil
            }
        }
        if !queue.isEmpty {
            return try queue.removeFirst().get()
        }
        return ExchangeRateTable(base: "USD", rates: ["USD": 1, "BRL": 5])
    }
}
