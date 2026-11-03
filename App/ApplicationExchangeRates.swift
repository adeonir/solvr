import AppKit
import SolvrCore

/// One rate service and durable cache for every sheet and window.
@MainActor
final class ApplicationExchangeRates: NSObject {
    static let shared = ApplicationExchangeRates()
    let service: ExchangeRateService
    private var timer: Timer?

    override private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        service = ExchangeRateService(
            source: CoinbaseExchangeRateSource(),
            cache: FileExchangeRateCache(url: folder.appending(path: "Solvr/exchange-rates.json"))
        )
        super.init()
    }

    func setForeground(_ foreground: Bool) {
        timer?.invalidate()
        timer = nil
        Task {
            await service.setForeground(foreground, now: Date())
            schedule()
        }
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard service.isForeground, let next = service.nextRefreshDate else { return }
        let timer = Timer(fireAt: next, interval: 0, target: self, selector: #selector(refresh), userInfo: nil, repeats: false)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func refresh() {
        // Check the real app state too: a pending timer cannot start a request
        // during a queued deactivation notification or after waking asleep.
        guard NSApp.isActive else { setForeground(false); return }
        Task {
            await service.refreshIfDue(now: Date())
            schedule()
        }
    }
}

@MainActor
final class SolvrApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        ApplicationExchangeRates.shared.setForeground(NSApp.isActive)
    }

    func applicationDidBecomeActive(_: Notification) {
        ApplicationExchangeRates.shared.setForeground(true)
    }

    func applicationDidResignActive(_: Notification) {
        ApplicationExchangeRates.shared.setForeground(false)
    }
}
