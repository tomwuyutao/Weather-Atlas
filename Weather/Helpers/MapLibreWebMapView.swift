import SwiftUI
import WebKit
import CoreLocation

#if os(macOS)
typealias PlatformWebViewRepresentable = NSViewRepresentable
#else
typealias PlatformWebViewRepresentable = UIViewRepresentable
#endif

struct MapLibreWebMapView: PlatformWebViewRepresentable {
    let cities: [CityWeather]
    let selectedDayOffset: Int
    var overlayMode: String = "weather"
    let filterSunny: Bool
    @Binding var tappedCity: CityWeather?
    @Binding var recenterOnAllCities: Bool
    var centerOnCity: CityWeather?
    var onMarkerTap: (CityWeather, CGPoint?) -> Void
    var onCameraMove: ((CLLocationCoordinate2D) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        dismantleWebView(nsView, coordinator: coordinator)
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        dismantleWebView(uiView, coordinator: coordinator)
    }
    #endif

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "mapEvent")
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        #if os(iOS)
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 0xED / 255.0, green: 0xE7 / 255.0, blue: 0xDE / 255.0, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = webView.backgroundColor
        }
        #elseif os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
        webView.loadHTMLString(Self.html, baseURL: Bundle.main.resourceURL)
        context.coordinator.webView = webView
        return webView
    }

    private func updateWebView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.webView = webView
        context.coordinator.pushStateIfReady()
    }

    private static func dismantleWebView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mapEvent")
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MapLibreWebMapView
        weak var webView: WKWebView?
        private var isReady = false
        private var lastPayload = ""
        private var lastStyleKey = ""
        private var lastCenteredCityID: UUID?
        private var observers: [NSObjectProtocol] = []

        init(parent: MapLibreWebMapView) {
            self.parent = parent
            super.init()
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .weatherZoomInCommand, object: nil, queue: .main) { [weak self] _ in
                self?.evaluate("window.weatherMapZoomIn?.();")
            })
            observers.append(center.addObserver(forName: .weatherZoomOutCommand, object: nil, queue: .main) { [weak self] _ in
                self?.evaluate("window.weatherMapZoomOut?.();")
            })
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
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
                let point: CGPoint?
                if let x = body["x"] as? Double, let y = body["y"] as? Double {
                    point = CGPoint(x: x, y: y)
                } else {
                    point = nil
                }
                parent.onMarkerTap(city, point)
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
        return cities.compactMap { cityWeather in
            guard passesFilter(cityWeather) else { return nil }
            let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
            let hasData = selectedDayOffset == -1
                ? cityWeather.hasCurrentData(forOverlay: overlayMode)
                : forecast.hasData(forOverlay: overlayMode)
            guard hasData else { return nil }

            let color = markerColor(for: cityWeather, forecast: forecast)
            return MapLibreWeatherFeature(
                id: cityWeather.id.uuidString,
                name: cityWeather.city.name,
                country: cityWeather.city.country,
                latitude: cityWeather.city.latitude,
                longitude: cityWeather.city.longitude,
                label: "",
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
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; min-height: 100%; overflow: hidden; background: #EDE7DE; }
        body { -webkit-user-select: none; user-select: none; position: fixed; inset: 0; }
        #map { position: fixed; inset: 0; width: 100vw; height: 100vh; height: 100dvh; background: #EDE7DE; }
        #window-drag-blur {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          height: 48px;
          z-index: 4;
          pointer-events: none;
          background: rgba(237, 231, 222, 0.24);
          -webkit-backdrop-filter: blur(18px) saturate(1.35);
          backdrop-filter: blur(18px) saturate(1.35);
          border-bottom: 1px solid rgba(255, 255, 255, 0.18);
        }
        body.dark-map #window-drag-blur {
          background: rgba(26, 27, 46, 0.24);
          border-bottom-color: rgba(255, 255, 255, 0.08);
        }
        .maplibregl-map, .maplibregl-canvas-container, .maplibregl-canvas { width: 100% !important; height: 100% !important; }
        .maplibregl-ctrl-logo, .maplibregl-ctrl-attrib { display: none !important; }
      </style>
    </head>
    <body>
      <div id="map"></div>
      <div id="window-drag-blur"></div>
      <script>
        let map;
        let loaded = false;
        let pendingPayload = null;
        let currentStyleMode = 'bright';
        let lastMovePost = 0;
        var baseStylePreferencesApplied = false;

        function styleURL(mode) {
          return mode === 'dark'
            ? 'https://tiles.openfreemap.org/styles/dark'
            : 'https://tiles.openfreemap.org/styles/bright';
        }

        function post(message) {
          window.webkit?.messageHandlers?.mapEvent?.postMessage(message);
        }

        function layerTextField(layer) {
          const value = layer?.layout?.['text-field'];
          return JSON.stringify(value || '').toLowerCase();
        }

        function layerSignature(layer) {
          const id = (layer.id || '').toLowerCase();
          const sourceLayer = (layer['source-layer'] || '').toLowerCase();
          const textField = layerTextField(layer);
          return `${id} ${sourceLayer} ${textField}`;
        }

        function themePalette(mode) {
          return mode === 'dark'
            ? { ocean: '#1A1B2E', land: '#252640', subtleLand: '#2D2E4A', road: '#353660' }
            : { ocean: '#EDE7DE', land: '#E0DAD1', subtleLand: '#E8E2D9', road: '#D5CFC6' };
        }

        function applyWarmMapPaint(layer, palette) {
          const combined = layerSignature(layer);
          layer.paint = layer.paint || {};

          if (layer.type === 'background') {
            layer.paint['background-color'] = palette.land;
            return;
          }

          if (layer.type === 'fill') {
            if (combined.includes('water') || combined.includes('ocean') || combined.includes('sea')) {
              layer.paint['fill-color'] = palette.ocean;
            } else if (combined.includes('park') || combined.includes('landcover') || combined.includes('landuse') || combined.includes('wood') || combined.includes('grass')) {
              layer.paint['fill-color'] = palette.subtleLand;
            } else {
              layer.paint['fill-color'] = palette.land;
            }
            layer.paint['fill-opacity'] = 1;
            return;
          }

          if (layer.type === 'line' && (combined.includes('road') || combined.includes('path') || combined.includes('track'))) {
            layer.paint['line-color'] = palette.road;
            layer.paint['line-opacity'] = 0.55;
          }
        }

        function shouldHideBaseLayer(layer) {
          const combined = layerSignature(layer);

          if (layer.type === 'line') {
            return combined.includes('boundary')
              || combined.includes('admin')
              || combined.includes('border')
              || combined.includes('disputed');
          }

          if (layer.type === 'symbol') {
            return combined.includes('country')
              || combined.includes('state')
              || combined.includes('province')
              || combined.includes('place_name:latin')
              || combined.includes('name:latin')
              || combined.includes('name:nonlatin')
              || combined.includes('place')
              || combined.includes('label');
          }

          return false;
        }

        async function cleanedStyle(mode) {
          const response = await fetch(styleURL(mode));
          const style = await response.json();
          const palette = themePalette(mode);
          style.layers = (style.layers || [])
            .filter(layer => !shouldHideBaseLayer(layer))
            .map(layer => {
              applyWarmMapPaint(layer, palette);
              return layer;
            });
          return style;
        }

        function applyWeatherMapStylePreferences() {
          if (!map || !map.isStyleLoaded() || baseStylePreferencesApplied) return;
          const style = map.getStyle();
          if (!style || !style.layers) return;

          const palette = themePalette(currentStyleMode);
          style.layers.forEach(layer => {
            if (shouldHideBaseLayer(layer)) {
              try { map.setLayoutProperty(layer.id, 'visibility', 'none'); } catch (_) {}
            } else {
              applyWarmMapPaint(layer, palette);
              try {
                Object.entries(layer.paint || {}).forEach(([key, value]) => map.setPaintProperty(layer.id, key, value));
              } catch (_) {}
            }
          });
          baseStylePreferencesApplied = true;
        }

        function ensureLayers() {
          if (!map || !map.isStyleLoaded()) return;
          applyWeatherMapStylePreferences();
          if (!map.getSource('weather')) {
            map.addSource('weather', { type: 'geojson', data: emptyCollection() });
          }
          if (!map.getLayer('weather-glow')) {
            map.addLayer({
              id: 'weather-glow', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['case', ['boolean', ['get', 'selected'], false], 20, 13],
                'circle-color': ['get', 'color'],
                'circle-opacity': ['case', ['boolean', ['get', 'selected'], false], 0.36, 0.24],
                'circle-blur': 0.85
              }
            });
          }
          if (!map.getLayer('weather-halo')) {
            map.addLayer({
              id: 'weather-halo', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['case', ['boolean', ['get', 'selected'], false], 11, 7],
                'circle-color': ['get', 'color'],
                'circle-opacity': ['case', ['boolean', ['get', 'selected'], false], 0.22, 0.14],
                'circle-blur': 0.45
              }
            });
          }
          if (!map.getLayer('weather-points')) {
            map.addLayer({
              id: 'weather-points', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['case', ['boolean', ['get', 'selected'], false], 6.5, 4.5],
                'circle-color': ['get', 'color'],
                'circle-stroke-color': 'rgba(255,255,255,0.0)',
                'circle-stroke-width': 0
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
          if (!bounds.isEmpty()) map.fitBounds(bounds, { padding: 180, duration: 550, maxZoom: 2.65 });
        };

        window.flyToCity = function(id) {
          const item = pendingPayload?.features?.find(feature => feature.id === id);
          if (item) map.flyTo({ center: [item.longitude, item.latitude], zoom: Math.max(map.getZoom(), 5), duration: 550 });
        };

        window.setMapStyleMode = async function(mode) {
          currentStyleMode = mode;
          document.body.classList.toggle('dark-map', mode === 'dark');
          baseStylePreferencesApplied = false;
          if (map) map.setStyle(await cleanedStyle(mode));
        };

        window.weatherMapZoomIn = function() {
          if (map) map.zoomIn({ duration: 220 });
        };

        window.weatherMapZoomOut = function() {
          if (map) map.zoomOut({ duration: 220 });
        };

        async function init() {
          map = new maplibregl.Map({
            container: 'map',
            style: await cleanedStyle(currentStyleMode),
            preserveDrawingBuffer: false,
            center: [0, 20],
            zoom: 1.45,
            minZoom: 1,
            maxZoom: 12,
            attributionControl: false
          });
          map.dragRotate.disable();
          map.touchZoomRotate.disableRotation();
          map.scrollZoom.enable();
          map.scrollZoom.setWheelZoomRate(1 / 220);
          map.scrollZoom.setZoomRate(1 / 70);
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
          map.on('click', event => {
            const hitBox = [
              [event.point.x - 18, event.point.y - 18],
              [event.point.x + 18, event.point.y + 18]
            ];
            const features = map.queryRenderedFeatures(hitBox, {
              layers: ['weather-points', 'weather-halo', 'weather-glow']
            });
            const feature = features && features[0];
            if (feature?.properties?.id) post({ type: 'markerTap', id: feature.properties.id, x: event.point.x, y: event.point.y });
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
          const pressedPanKeys = new Set();
          let panAnimationFrame = null;

          function panLoop() {
            if (!pressedPanKeys.size) {
              panAnimationFrame = null;
              return;
            }
            let x = 0;
            let y = 0;
            const step = 12;
            if (pressedPanKeys.has('w')) y -= step;
            if (pressedPanKeys.has('a')) x -= step;
            if (pressedPanKeys.has('s')) y += step;
            if (pressedPanKeys.has('d')) x += step;
            if (x !== 0 || y !== 0) map.panBy([x, y], { duration: 0 });
            panAnimationFrame = requestAnimationFrame(panLoop);
          }

          function startPanLoop() {
            if (!panAnimationFrame) panAnimationFrame = requestAnimationFrame(panLoop);
          }

          window.addEventListener('keydown', event => {
            const key = event.key.toLowerCase();
            if (event.metaKey && (key === '+' || key === '=')) {
              event.preventDefault();
              window.weatherMapZoomIn();
              return;
            }
            if (event.metaKey && key === '-') {
              event.preventDefault();
              window.weatherMapZoomOut();
              return;
            }
            if (event.metaKey || event.ctrlKey || event.altKey) return;

            if (['w', 'a', 's', 'd'].includes(key)) {
              event.preventDefault();
              pressedPanKeys.add(key);
              startPanLoop();
            }
          });
          window.addEventListener('keyup', event => {
            pressedPanKeys.delete(event.key.toLowerCase());
          });
          window.addEventListener('blur', () => {
            pressedPanKeys.clear();
          });
        }

        if (window.maplibregl) init().catch(error => console.error('Map init failed', error));
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
