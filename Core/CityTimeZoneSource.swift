import Foundation

public enum CityLookupError: Error, Sendable, Equatable {
    /// The response is not the city data the source documents.
    case invalidResponse
    case httpStatus(Int)
}

/// One city lookup against the external city data source.
public protocol CityTimeZoneSource: Sendable {
    /// The records the source returns for a city name; an empty answer when
    /// the source knows no place of that name.
    func lookup(_ city: String) async throws -> [CityRecord]
}

/// The Open-Meteo Geocoding API, which returns city records with their
/// time zone database identifier.
public struct OpenMeteoGeocodingSource: CityTimeZoneSource {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
    private let transport: Transport

    public init(transport: @escaping Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }) {
        self.transport = transport
    }

    public func lookup(_ city: String) async throws -> [CityRecord] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw CityLookupError.invalidResponse }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let (data, status) = try await transport(request)
        guard (200 ..< 300).contains(status) else { throw CityLookupError.httpStatus(status) }
        struct Response: Decodable {
            struct Place: Decodable {
                let name: String
                let country: String?
                let admin1: String?
                let timezone: String?
                let population: Int?
            }

            let results: [Place]?
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw CityLookupError.invalidResponse
        }
        return (response.results ?? []).map { place in
            CityRecord(
                name: place.name,
                country: place.country,
                region: place.admin1,
                timeZoneIdentifier: place.timezone ?? "",
                population: place.population
            )
        }
    }
}
