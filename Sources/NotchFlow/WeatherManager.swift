import Combine
import CoreLocation
import Foundation

// Local weather via Open-Meteo (free, no API key) + CoreLocation for the
// coordinate. Opt-in: nothing runs and no location prompt appears until the
// user turns it on in settings. Public API only.
final class WeatherManager: NSObject, ObservableObject {
    static let shared = WeatherManager()

    @Published private(set) var weather: Weather?

    private let locationManager = CLLocationManager()
    private var coordinate: CLLocationCoordinate2D?
    private var refreshTimer: Timer?

    // Locale decides units (US → Fahrenheit) so the reading matches the rest
    // of the system without a manual toggle.
    private var fahrenheit: Bool { Locale.current.measurementSystem == .us }
    private var unitParam: String { fahrenheit ? "fahrenheit" : "celsius" }
    private var unitLabel: String { fahrenheit ? "°F" : "°C" }

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced // city-level is plenty
    }

    /// Begin tracking: prompts for location the first time, then fetches now and
    /// every 30 minutes. Idempotent.
    func start() {
        guard refreshTimer == nil else { return }
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestLocation()
        let timer = Timer(timeInterval: 1800, repeats: true) { [weak self] _ in
            self?.locationManager.requestLocation()   // re-read coord + weather
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        coordinate = nil
        weather = nil
    }

    private func fetch(_ coord: CLLocationCoordinate2D) {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(coord.latitude)),
            .init(name: "longitude", value: String(coord.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "temperature_unit", value: unitParam),
        ]
        guard let url = comps.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let w = Weather.parse(data, unit: self.unitLabel) else { return }
            DispatchQueue.main.async { self.weather = w }
        }.resume()
    }
}

extension WeatherManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        coordinate = coord
        fetch(coord)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failure (no fix yet, denied) — keep the last reading if any;
        // the next timer tick retries. No crash, no spam.
    }
}
