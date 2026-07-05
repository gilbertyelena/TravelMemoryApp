//
//  WeatherService.swift
//  TravelMemory
//
//  Daily forecast chips for trip days via Open-Meteo — free, no API
//  key, no entitlement (unlike WeatherKit). Fails silently offline.
//

import Foundation
import CoreLocation

struct DayWeather {
    let symbol: String
    let maxTemp: Double
    let minTemp: Double

    var chipText: String {
        "\(Int(maxTemp.rounded()))°"
    }
}

@MainActor
final class WeatherService: ObservableObject {
    /// Forecast per start-of-day, filled after fetch(for:) succeeds
    @Published var daily: [Date: DayWeather] = [:]

    private var fetchedForTripID: UUID?

    func fetch(for trip: Trip) {
        // One fetch per trip per service lifetime; forecasts move slowly
        guard fetchedForTripID != trip.id else { return }
        let destination = trip.destination.isEmpty ? trip.name : trip.destination
        guard !destination.isEmpty else { return }

        // Open-Meteo forecasts ~16 days out; skip far-future/past trips
        let horizon = Date().addingTimeInterval(16 * 24 * 3600)
        guard trip.startDate < horizon, trip.endDate > Date().addingTimeInterval(-24 * 3600) else { return }

        fetchedForTripID = trip.id
        let tripID = trip.id
        let startDate = max(trip.startDate, Date())
        let endDate = min(trip.endDate, horizon)

        CLGeocoder().geocodeAddressString(destination) { [weak self] placemarks, _ in
            guard let coordinate = placemarks?.first?.location?.coordinate else { return }
            Task { @MainActor [weak self] in
                await self?.fetchForecast(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    from: startDate,
                    to: endDate,
                    tripID: tripID
                )
            }
        }
    }

    private func fetchForecast(latitude: Double, longitude: Double, from: Date, to: Date, tripID: UUID) async {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: fmt.string(from: from)),
            URLQueryItem(name: "end_date", value: fmt.string(from: to)),
        ]
        guard let url = components.url else { return }

        struct Response: Decodable {
            struct Daily: Decodable {
                let time: [String]
                let weather_code: [Int]
                let temperature_2m_max: [Double]
                let temperature_2m_min: [Double]
            }
            let daily: Daily
        }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            return
        }

        // Ignore a stale response if the user switched trips meanwhile
        guard fetchedForTripID == tripID else { return }

        var result: [Date: DayWeather] = [:]
        let cal = Calendar.current
        for (index, dayString) in decoded.daily.time.enumerated() {
            guard let date = fmt.date(from: dayString),
                  index < decoded.daily.weather_code.count,
                  index < decoded.daily.temperature_2m_max.count,
                  index < decoded.daily.temperature_2m_min.count else { continue }
            result[cal.startOfDay(for: date)] = DayWeather(
                symbol: Self.symbol(for: decoded.daily.weather_code[index]),
                maxTemp: decoded.daily.temperature_2m_max[index],
                minTemp: decoded.daily.temperature_2m_min[index]
            )
        }
        daily = result
    }

    /// WMO weather code → SF Symbol
    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max"
        case 1, 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51...57: return "cloud.drizzle"
        case 61...67: return "cloud.rain"
        case 71...77: return "cloud.snow"
        case 80...82: return "cloud.heavyrain"
        case 85, 86: return "cloud.snow"
        case 95...99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }
}
