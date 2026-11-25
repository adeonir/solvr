import AppKit
import Core

@MainActor
final class ApplicationCityTimeZones {
    static let shared = ApplicationCityTimeZones()
    let service: CityTimeZoneService

    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        service = CityTimeZoneService(
            source: OpenMeteoGeocodingSource(),
            cache: FileCityTimeZoneCache(url: folder.appending(path: "Solvr/city-time-zones.json"))
        )
    }

    func resolve(_ cities: Set<String>) {
        guard !cities.isEmpty else { return }
        Task {
            await service.resolve(cities, now: Date())
        }
    }
}
