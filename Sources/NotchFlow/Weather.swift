import Foundation

// Pure weather model — parses an Open-Meteo "current" response and maps WMO
// weather codes to SF Symbols. Foundation-only so it runs in the swiftc test
// harness (mirrors the NowPlaying / NowPlayingManager split).
struct Weather: Equatable {
    let temp: Int          // already in the requested unit, rounded
    let unit: String       // "°C" / "°F"
    let symbol: String     // SF Symbol name

    var label: String { "\(temp)\(unit)" }

    /// Decode `{"current":{"temperature_2m":12.3,"weather_code":3}}`.
    static func parse(_ data: Data, unit: String) -> Weather? {
        guard let root = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return Weather(temp: Int(root.current.temperature_2m.rounded()),
                       unit: unit,
                       symbol: symbol(for: root.current.weather_code))
    }

    private struct Response: Decodable { let current: Current }
    private struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }

    /// WMO weather code → SF Symbol. Bucketed, not exhaustive — the ~28 WMO
    /// codes collapse to a handful of glyphs a user can tell apart at a glance.
    /// ponytail: coarse buckets; split further only if the extra glyphs read.
    static func symbol(for code: Int) -> String {
        switch code {
        case 0:               return "sun.max.fill"            // clear
        case 1, 2:            return "cloud.sun.fill"          // mainly clear / partly cloudy
        case 3:               return "cloud.fill"              // overcast
        case 45, 48:          return "cloud.fog.fill"          // fog
        case 51...57:         return "cloud.drizzle.fill"      // drizzle
        case 61...67, 80...82: return "cloud.rain.fill"        // rain / showers
        case 71...77, 85, 86: return "cloud.snow.fill"         // snow
        case 95...99:         return "cloud.bolt.rain.fill"    // thunderstorm
        default:              return "cloud.fill"
        }
    }
}
