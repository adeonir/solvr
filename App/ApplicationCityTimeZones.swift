import AppKit
import NumeCore

/// One city data service and durable cache for every sheet and window.
@MainActor
final class ApplicationCityTimeZones {
    static let shared = ApplicationCityTimeZones()
    let service: CityTimeZoneService

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        service = CityTimeZoneService(
            source: OpenMeteoGeocodingSource(),
            cache: FileCityTimeZoneCache(url: folder.appending(path: "Nume/city-time-zones.json"))
        )
    }

    /// Looks up the cities the open sheet could not resolve yet. The cache
    /// keeps the last usable answer, so an offline app keeps converting the
    /// cities it resolved before.
    func resolve(_ cities: Set<String>) {
        guard !cities.isEmpty else { return }
        Task {
            await service.resolve(cities, now: Date())
        }
    }
}
