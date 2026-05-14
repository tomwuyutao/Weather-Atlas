import SwiftUI
import WebKit
import CoreLocation

struct MapLibreWebMapView: UIViewRepresentable {
    let cities: [CityWeather]
    let selectedDayOffset: Int
    var overlayMode: String = "weather"
    let filterSunny: Bool
    @Binding var tappedCity: CityWeather?
    @Binding var recenterOnAllCities: Bool
    var centerOnCity: CityWeather?
    var onMarkerTap: (CityWeather) -> Void
    var onCameraMove: ((CLLocationCoordinate2D) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "mapEvent")
        configuration.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 0xDD / 255.0, green: 0xE9 / 255.0, blue: 0xEF / 255.0, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = webView.backgroundColor
        }
        webView.loadHTMLString(Self.html, baseURL: Bundle.main.resourceURL)
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.webView = webView
        context.coordinator.pushStateIfReady()
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "mapEvent")
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MapLibreWebMapView
        weak var webView: WKWebView?
        private var isReady = false
        private var lastPayload = ""
        private var lastStyleKey = ""
        private var lastCenteredCityID: UUID?

        init(parent: MapLibreWebMapView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            pushStateIfReady(force: true)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mapEvent",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                isReady = true
                pushStateIfReady(force: true)
            case "markerTap":
                guard let id = body["id"] as? String,
                      let city = parent.cities.first(where: { $0.id.uuidString == id }) else { return }
                parent.onMarkerTap(city)
            case "cameraMove":
                guard let lat = body["lat"] as? Double,
                      let lng = body["lng"] as? Double else { return }
                parent.onCameraMove?(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            default:
                break
            }
        }

        func pushStateIfReady(force: Bool = false) {
            guard isReady, webView != nil else { return }

            let styleKey = parent.colorScheme == .dark ? "dark" : "bright"
            if force || styleKey != lastStyleKey {
                lastStyleKey = styleKey
                evaluate("window.setMapStyleMode(\(Self.jsString(styleKey)));")
            }

            let features = parent.makeFeatures()
            guard let data = try? JSONEncoder().encode(features),
                  let json = String(data: data, encoding: .utf8) else { return }
            let selectedID = parent.tappedCity?.id.uuidString ?? ""
            let payload = "{features:\(json),selectedID:\(Self.jsString(selectedID))}"

            if force || payload != lastPayload {
                lastPayload = payload
                evaluate("window.updateWeatherData(\(payload));")
            }

            if parent.recenterOnAllCities {
                evaluate("window.fitWeatherData();")
                DispatchQueue.main.async {
                    self.parent.recenterOnAllCities = false
                }
            }

            if let centerOnCity = parent.centerOnCity, centerOnCity.id != lastCenteredCityID {
                lastCenteredCityID = centerOnCity.id
                evaluate("window.flyToCity(\(Self.jsString(centerOnCity.id.uuidString))); ")
            }
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script)
        }

        private static func jsString(_ value: String) -> String {
            guard let data = try? JSONEncoder().encode(value),
                  let string = String(data: data, encoding: .utf8) else { return "\"\"" }
            return string
        }
    }

    private func makeFeatures() -> [MapLibreWeatherFeature] {
        let tempUnit = TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
        let distUnit = DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
        return cities.compactMap { cityWeather in
            guard passesFilter(cityWeather) else { return nil }
            let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
            let hasData = selectedDayOffset == -1
                ? cityWeather.hasCurrentData(forOverlay: overlayMode)
                : forecast.hasData(forOverlay: overlayMode)
            guard hasData else { return nil }

            let label = markerLabel(for: cityWeather, forecast: forecast, tempUnit: tempUnit, distUnit: distUnit)
            let color = markerColor(for: cityWeather, forecast: forecast)
            return MapLibreWeatherFeature(
                id: cityWeather.id.uuidString,
                name: cityWeather.city.name,
                country: cityWeather.city.country,
                latitude: cityWeather.city.latitude,
                longitude: cityWeather.city.longitude,
                label: label,
                color: color
            )
        }
    }

    private func passesFilter(_ cityWeather: CityWeather) -> Bool {
        guard filterSunny else { return true }
        if selectedDayOffset == -1 {
            return cityWeather.condition == .clear && !cityWeather.weatherIcon.contains("moon")
        }
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        return forecast.condition == .clear && !forecast.weatherIcon.contains("moon")
    }

    private func markerLabel(for cityWeather: CityWeather, forecast: DailyForecast, tempUnit: TemperatureUnit, distUnit: DistanceUnit) -> String {
        let isNow = selectedDayOffset == -1
        switch overlayMode {
        case "cloudCover":
            if isNow { return cityWeather.currentCloudCover.map { "\(Int($0 * 100))%" } ?? "-" }
            return forecast.cloudCoverPercent.map { "\($0)%" } ?? "-"
        case "precipitation":
            if isNow { return [.rain, .drizzle, .snow].contains(cityWeather.condition) ? "100%" : "0%" }
            return forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "-"
        case "windSpeed":
            if isNow { return cityWeather.currentWindSpeed.map { distUnit.displayWindSpeed($0) } ?? "-" }
            return forecast.windSpeed.map { distUnit.displayWindSpeed($0) } ?? "-"
        case "uvIndex":
            if isNow { return cityWeather.currentUVIndex.map(String.init) ?? "-" }
            return forecast.uvIndex.map(String.init) ?? "-"
        case "humidity":
            if isNow { return cityWeather.currentHumidity.map { "\(Int($0 * 100))%" } ?? "-" }
            return forecast.maxHumidity.map { "\(Int($0 * 100))%" } ?? "-"
        case "visibility":
            if isNow { return cityWeather.currentVisibility.map { distUnit.display($0) } ?? "-" }
            return forecast.maxVisibility.map { distUnit.display($0) } ?? "-"
        default:
            return tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh)
        }
    }

    private func markerColor(for cityWeather: CityWeather, forecast: DailyForecast) -> String {
        let isNow = selectedDayOffset == -1
        if overlayMode == "temperature" {
            return temperatureColor(isNow ? cityWeather.temperature : forecast.dailyHigh)
        }
        if overlayMode == "cloudCover" {
            let value = isNow ? cityWeather.currentCloudCover : forecast.cloudCover
            return blendHex(from: 0x1579C7, to: 0xFFFFFF, amount: value ?? 0.5)
        }
        if overlayMode == "precipitation" {
            let chance: Double
            if isNow {
                chance = [.rain, .drizzle, .snow].contains(cityWeather.condition) ? 1 : 0
            } else {
                chance = forecast.precipitationChance ?? 0.5
            }
            return blendHex(from: 0xFFFFFF, to: 0x57D3E5, amount: chance)
        }
        if overlayMode == "windSpeed" {
            let windSpeed = (isNow ? cityWeather.currentWindSpeed : forecast.windSpeed) ?? 0
            let wind = min(1, windSpeed / 100)
            return blendHex(from: 0xFFFFFF, to: 0xFDA409, amount: wind)
        }
        if overlayMode == "uvIndex" {
            let uv = min(1, Double((isNow ? cityWeather.currentUVIndex : forecast.uvIndex) ?? 0) / 11)
            return blendHex(from: 0xFFFFFF, to: 0xFB4368, amount: uv)
        }
        if overlayMode == "humidity" {
            return blendHex(from: 0xFFFFFF, to: 0xBE9AED, amount: (isNow ? cityWeather.currentHumidity : forecast.maxHumidity) ?? 0.5)
        }
        if overlayMode == "visibility" {
            let visibility = min(1, ((isNow ? cityWeather.currentVisibility : forecast.maxVisibility) ?? 15) / 30)
            return blendHex(from: 0xFFFFFF, to: 0x1579C7, amount: visibility)
        }
        let condition = isNow ? cityWeather.condition : forecast.condition
        return color(for: condition, icon: isNow ? cityWeather.weatherIcon : forecast.weatherIcon)
    }

    private func color(for condition: AppWeatherCondition, icon: String) -> String {
        if icon.contains("moon") { return "#BE9AED" }
        switch condition {
        case .clear: return "#FDA409"
        case .partlyCloudy: return "#F5C563"
        case .cloudy: return "#FFFFFF"
        case .rain: return "#1579C7"
        case .drizzle: return "#57D3E5"
        case .snow: return "#FFFFFF"
        case .fog: return "#FFFFFF"
        case .wind: return "#FFFFFF"
        }
    }

    private func temperatureColor(_ tempC: Double) -> String {
        if tempC <= 0 {
            return blendHex(from: 0x1579C7, to: 0x57D3E5, amount: max(0, min(1, (tempC + 20) / 20)))
        }
        if tempC <= 10 {
            return blendHex(from: 0x57D3E5, to: 0x7DD4A0, amount: max(0, min(1, tempC / 10)))
        }
        if tempC <= 20 {
            return blendHex(from: 0x7DD4A0, to: 0xFDA409, amount: max(0, min(1, (tempC - 10) / 10)))
        }
        return blendHex(from: 0xFDA409, to: 0xFB4368, amount: max(0, min(1, (tempC - 20) / 20)))
    }

    private func blendHex(from: Int, to: Int, amount: Double) -> String {
        let t = max(0, min(1, amount))
        let r1 = Double((from >> 16) & 0xFF)
        let g1 = Double((from >> 8) & 0xFF)
        let b1 = Double(from & 0xFF)
        let r2 = Double((to >> 16) & 0xFF)
        let g2 = Double((to >> 8) & 0xFF)
        let b2 = Double(to & 0xFF)
        let r = Int(r1 + (r2 - r1) * t)
        let g = Int(g1 + (g2 - g1) * t)
        let b = Int(b1 + (b2 - b1) * t)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static let html = """
    <!doctype html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
      <link rel="stylesheet" href="https://unpkg.com/maplibre-gl/dist/maplibre-gl.css">
      <script src="https://unpkg.com/maplibre-gl/dist/maplibre-gl.js"></script>
      <style>
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; min-height: 100%; overflow: hidden; background: #DDE9EF; }
        body { -webkit-user-select: none; user-select: none; position: fixed; inset: 0; }
        #map { position: fixed; inset: 0; width: 100vw; height: 100vh; height: 100dvh; background: #DDE9EF; }
        .maplibregl-map, .maplibregl-canvas-container, .maplibregl-canvas { width: 100% !important; height: 100% !important; }
        .maplibregl-ctrl-logo, .maplibregl-ctrl-attrib { display: none !important; }
      </style>
    </head>
    <body>
      <div id="map"></div>
      <script>
        let map;
        let loaded = false;
        let pendingPayload = null;
        let currentStyleMode = 'bright';
        let lastMovePost = 0;

        function styleURL(mode) {
          return mode === 'dark'
            ? 'https://tiles.openfreemap.org/styles/dark'
            : 'https://tiles.openfreemap.org/styles/bright';
        }

        function post(message) {
          window.webkit?.messageHandlers?.mapEvent?.postMessage(message);
        }

        function ensureLayers() {
          if (!map || !map.isStyleLoaded()) return;
          if (!map.getSource('weather')) {
            map.addSource('weather', { type: 'geojson', data: emptyCollection() });
          }
          if (!map.getLayer('weather-halo')) {
            map.addLayer({
              id: 'weather-halo', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['case', ['boolean', ['get', 'selected'], false], 14, 10],
                'circle-color': ['get', 'color'],
                'circle-opacity': ['case', ['boolean', ['get', 'selected'], false], 0.28, 0.14],
                'circle-blur': 0.35
              }
            });
          }
          if (!map.getLayer('weather-points')) {
            map.addLayer({
              id: 'weather-points', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['case', ['boolean', ['get', 'selected'], false], 7, 4.5],
                'circle-color': ['get', 'color'],
                'circle-stroke-color': 'rgba(255,255,255,0.85)',
                'circle-stroke-width': ['case', ['boolean', ['get', 'selected'], false], 1.5, 0.6]
              }
            });
          }
          if (!map.getLayer('weather-labels')) {
            map.addLayer({
              id: 'weather-labels', type: 'symbol', source: 'weather',
              minzoom: 2,
              layout: {
                'text-field': ['get', 'label'],
                'text-size': 12,
                'text-font': ['Noto Sans Regular'],
                'text-anchor': 'bottom',
                'text-offset': [0, -0.9],
                'text-allow-overlap': false,
                'text-optional': true
              },
              paint: {
                'text-color': '#ffffff',
                'text-halo-color': 'rgba(0,0,0,0.45)',
                'text-halo-width': 1.2
              }
            });
          }
        }

        function emptyCollection() {
          return { type: 'FeatureCollection', features: [] };
        }

        function collectionFromPayload(payload) {
          const selectedID = payload.selectedID || '';
          return {
            type: 'FeatureCollection',
            features: (payload.features || []).map(item => ({
              type: 'Feature',
              id: item.id,
              properties: {
                id: item.id,
                name: item.name,
                country: item.country,
                label: item.label,
                color: item.color,
                selected: item.id === selectedID
              },
              geometry: { type: 'Point', coordinates: [item.longitude, item.latitude] }
            }))
          };
        }

        function updateSource(payload) {
          pendingPayload = payload;
          ensureLayers();
          const source = map?.getSource('weather');
          if (source) source.setData(collectionFromPayload(payload));
        }

        window.updateWeatherData = function(payload) {
          if (!loaded) { pendingPayload = payload; return; }
          updateSource(payload);
        };

        window.fitWeatherData = function() {
          if (!pendingPayload || !pendingPayload.features || pendingPayload.features.length === 0) return;
          const bounds = new maplibregl.LngLatBounds();
          pendingPayload.features.forEach(item => bounds.extend([item.longitude, item.latitude]));
          if (!bounds.isEmpty()) map.fitBounds(bounds, { padding: 70, duration: 550, maxZoom: 7 });
        };

        window.flyToCity = function(id) {
          const item = pendingPayload?.features?.find(feature => feature.id === id);
          if (item) map.flyTo({ center: [item.longitude, item.latitude], zoom: Math.max(map.getZoom(), 5), duration: 550 });
        };

        window.setMapStyleMode = function(mode) {
          currentStyleMode = mode;
          if (map) map.setStyle(styleURL(mode));
        };

        function init() {
          map = new maplibregl.Map({
            container: 'map',
            style: styleURL(currentStyleMode),
            preserveDrawingBuffer: false,
            center: [0, 20],
            zoom: 1.45,
            minZoom: 1,
            maxZoom: 12,
            attributionControl: false
          });
          map.dragRotate.disable();
          map.touchZoomRotate.disableRotation();
          map.on('load', () => {
            loaded = true;
            ensureLayers();
            if (pendingPayload) updateSource(pendingPayload);
            post({ type: 'ready' });
          });
          map.on('styledata', () => {
            if (!loaded) return;
            ensureLayers();
            if (pendingPayload) updateSource(pendingPayload);
          });
          map.on('click', 'weather-points', event => {
            const feature = event.features && event.features[0];
            if (feature?.properties?.id) post({ type: 'markerTap', id: feature.properties.id });
          });
          map.on('mouseenter', 'weather-points', () => { map.getCanvas().style.cursor = 'pointer'; });
          map.on('mouseleave', 'weather-points', () => { map.getCanvas().style.cursor = ''; });
          map.on('move', () => {
            const now = Date.now();
            if (now - lastMovePost < 120) return;
            lastMovePost = now;
            const center = map.getCenter();
            post({ type: 'cameraMove', lat: center.lat, lng: center.lng });
          });
        }

        if (window.maplibregl) init();
      </script>
    </body>
    </html>
    """
}

private struct MapLibreWeatherFeature: Codable {
    let id: String
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    let label: String
    let color: String
}
