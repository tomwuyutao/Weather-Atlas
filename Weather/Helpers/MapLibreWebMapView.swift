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
    var leadingFitPadding: Double = 0
    var focusSelectedMarker: Bool = true
    var allowsMarkerHover: Bool = true
    var cameraProfile: MapCameraProfile = .desktop
    var onMarkerTap: (CityWeather, CGPoint?) -> Void
    var onMapClick: ((CLLocationCoordinate2D, CGPoint?) -> Void)? = nil
    var onMarkerCommandHover: ((CityWeather?, CGPoint?) -> Void)? = nil
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
            observers.append(center.addObserver(forName: .weatherPanCommand, object: nil, queue: .main) { [weak self] notification in
                guard let key = notification.object as? String else { return }
                self?.evaluate("window.weatherMapStep?.(\(Self.jsString(key)));")
            })
            observers.append(center.addObserver(forName: .weatherKeyboardZoomCommand, object: nil, queue: .main) { [weak self] notification in
                guard let key = notification.object as? String else { return }
                self?.evaluate("window.weatherMapKeyboardZoom?.(\(Self.jsString(key)));")
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
            case "mapBackgroundClick":
                guard let lat = body["lat"] as? Double,
                      let lng = body["lng"] as? Double else { return }
                let point: CGPoint?
                if let x = body["x"] as? Double, let y = body["y"] as? Double {
                    point = CGPoint(x: x, y: y)
                } else {
                    point = nil
                }
                parent.onMapClick?(CLLocationCoordinate2D(latitude: lat, longitude: lng), point)
            case "markerCommandHover":
                guard let id = body["id"] as? String,
                      let city = parent.cities.first(where: { $0.id.uuidString == id }) else { return }
                let point: CGPoint?
                if let x = body["x"] as? Double, let y = body["y"] as? Double {
                    point = CGPoint(x: x, y: y)
                } else {
                    point = nil
                }
                parent.onMarkerCommandHover?(city, point)
            case "markerCommandHoverEnd":
                parent.onMarkerCommandHover?(nil, nil)
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

            evaluate("window.setWeatherMapCameraProfile?.(\(Self.jsString(parent.cameraProfile.rawValue)));")

            let features = parent.makeFeatures()
            guard let data = try? JSONEncoder().encode(features),
                  let json = String(data: data, encoding: .utf8) else { return }
            let selectedID = parent.focusSelectedMarker ? (parent.tappedCity?.id.uuidString ?? "") : ""
            let payload = "{features:\(json),selectedID:\(Self.jsString(selectedID)),allowsMarkerHover:\(parent.allowsMarkerHover ? "true" : "false")}"

            if force || payload != lastPayload {
                lastPayload = payload
                evaluate("window.updateWeatherData(\(payload));")
            }

            if parent.recenterOnAllCities {
                evaluate("window.fitWeatherData(\(parent.leadingFitPadding));")
                DispatchQueue.main.async {
                    self.parent.recenterOnAllCities = false
                }
            }

            if let centerOnCity = parent.centerOnCity, centerOnCity.id != lastCenteredCityID {
                lastCenteredCityID = centerOnCity.id
                evaluate("window.flyToCity(\(Self.jsString(centerOnCity.id.uuidString)), \(parent.leadingFitPadding)); ")
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
            let isHiddenByFilter = filterSunny && !passesFilter(cityWeather)
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
                color: color,
                hidden: isHiddenByFilter
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
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; min-height: 100%; overflow: hidden; background: #F4F1EB; }
        body { -webkit-user-select: none; user-select: none; position: fixed; inset: 0; }
        #map { position: fixed; inset: 0; width: 100vw; height: 100vh; height: 100dvh; background: #F4F1EB; }
        #window-drag-blur {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          height: 54px;
          z-index: 4;
          pointer-events: none;
          background: rgba(237, 231, 222, 0.10);
          -webkit-backdrop-filter: blur(10px) saturate(1.12);
          backdrop-filter: blur(10px) saturate(1.12);
          border-bottom: 1px solid rgba(255, 255, 255, 0.08);
          display: none;
        }
        body.desktop-camera #window-drag-blur {
          display: block;
        }
        body.dark-map #window-drag-blur {
          background: rgba(26, 27, 46, 0.10);
          border-bottom-color: rgba(255, 255, 255, 0.04);
        }
        .maplibregl-map, .maplibregl-canvas-container, .maplibregl-canvas { width: 100% !important; height: 100% !important; cursor: default !important; }
        .maplibregl-canvas { transition: filter 220ms ease; }
        body.focus-selected .maplibregl-canvas { filter: saturate(0.82) brightness(0.94); }
        .maplibregl-ctrl-logo, .maplibregl-ctrl-attrib { display: none !important; }
        #hover-label {
          position: fixed;
          z-index: 5;
          padding: 4px 8px;
          border-radius: 999px;
          font: 600 12px -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
          color: #1F1F1F;
          background: rgba(244, 241, 235, 0.88);
          opacity: 0;
          transform: translate(-50%, -100%) translateY(-20px);
          pointer-events: none;
          transition: opacity 100ms ease, transform 100ms ease;
          box-shadow: 0 6px 18px rgba(0, 0, 0, 0.14);
          -webkit-backdrop-filter: blur(18px) saturate(1.2);
          backdrop-filter: blur(18px) saturate(1.2);
          white-space: nowrap;
        }
        body.dark-map #hover-label {
          color: #E8E4DF;
          background: rgba(26, 27, 46, 0.88);
        }
        #hover-label.visible {
          opacity: 1;
          transform: translate(-50%, -100%) translateY(-16px);
        }
      </style>
    </head>
    <body>
      <div id="map"></div>
      <div id="window-drag-blur"></div>
      <div id="hover-label"></div>
      <script>
        var map;
        var loaded = false;
        var pendingPayload = null;
        var currentStyleMode = 'bright';
        var lastMovePost = 0;
        var hoveredMarkerID = '';
        var hoveredMarkerPoint = null;
        var commandPressed = false;
        var commandHoverCardID = '';
        var selectedMarkerID = '';
        var markerScales = {};
        var markerVisibilityScales = {};
        var markerScaleAnimationFrame = null;
        var selectedPulseAnimationFrame = null;
        var selectedPulse = 0;
        var pinchVelocity = 0;
        var pinchAnimationFrame = null;
        var baseStylePreferencesApplied = false;
        var leftMouseDown = null;
        var cameraProfile = (/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) ? 'mobile' : 'desktop';
        const cameraProfiles = {
          desktop: {
            initialCenter: [0, 20],
            initialZoom: 1.45,
            fitPadding: { top: 180, right: 180, bottom: 180, left: 180 },
            fitMaxZoom: 2.65,
            cityZoom: 5,
            useLeadingOffset: true
          },
          mobile: {
            initialCenter: [0, 12],
            initialZoom: 1.15,
            fitPadding: { top: 104, right: 52, bottom: 168, left: 52 },
            fitMaxZoom: 4.2,
            cityZoom: 4.35,
            useLeadingOffset: false
          }
        };

        function styleURL(mode) {
          return mode === 'dark'
            ? 'https://tiles.openfreemap.org/styles/dark'
            : 'https://tiles.openfreemap.org/styles/bright';
        }

        function post(message) {
          window.webkit?.messageHandlers?.mapEvent?.postMessage(message);
        }

        function activeCameraProfile() {
          return cameraProfiles[cameraProfile] || cameraProfiles.desktop;
        }

        function applyCameraProfileClass() {
          document.body.classList.toggle('desktop-camera', cameraProfile === 'desktop');
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
            : { ocean: '#F4F1EB', land: '#E8E5DF', subtleLand: '#EFEBE5', road: '#DDDAD3' };
        }

        function isRoadLikeLayer(combined) {
          return combined.includes('road')
            || combined.includes('street')
            || combined.includes('transport')
            || combined.includes('highway')
            || combined.includes('motorway')
            || combined.includes('trunk')
            || combined.includes('primary')
            || combined.includes('secondary')
            || combined.includes('tertiary')
            || combined.includes('minor')
            || combined.includes('service')
            || combined.includes('path')
            || combined.includes('track')
            || combined.includes('rail');
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

          if (layer.type === 'line' && isRoadLikeLayer(combined)) {
            layer.layout = layer.layout || {};
            layer.layout.visibility = 'none';
          }

          if (layer.type === 'symbol' && (combined.includes('place') || combined.includes('label') || combined.includes('name'))) {
            layer.minzoom = Math.max(layer.minzoom || 0, 6.2);
          }
        }

        function shouldHideBaseLayer(layer) {
          const combined = layerSignature(layer);

          if (layer.type === 'line') {
            return combined.includes('boundary')
              || combined.includes('admin')
              || combined.includes('border')
              || combined.includes('disputed')
              || isRoadLikeLayer(combined)
              || combined.includes('ferry')
              || combined.includes('marine')
              || combined.includes('navigation')
              || combined.includes('shipping');
          }

          if (layer.type === 'symbol') {
            return combined.includes('country')
              || combined.includes('ocean')
              || combined.includes('sea')
              || combined.includes('marine label')
              || combined.includes('water label')
              || combined.includes('water_name')
              || combined.includes('water-name')
              || isRoadLikeLayer(combined)
              || combined.includes('ferry')
              || combined.includes('marine')
              || combined.includes('navigation')
              || combined.includes('shipping')
              || combined.includes('state')
              || combined.includes('province');
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
          if (!map.getLayer('weather-hit')) {
            map.addLayer({
              id: 'weather-hit', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['*', ['number', ['get', 'visibleScale'], 1], 11],
                'circle-color': 'rgba(0,0,0,0.01)',
                'circle-opacity': 0.01
              }
            });
          }
          if (!map.getLayer('weather-glow')) {
            map.addLayer({
              id: 'weather-glow', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['*', ['number', ['get', 'visibleScale'], 1], ['+', 13, ['*', ['number', ['get', 'selectedPulse'], 0], 13]]],
                'circle-color': ['get', 'color'],
                'circle-opacity': ['*',
                  ['number', ['get', 'visibleScale'], 1],
                  ['case',
                    ['boolean', ['get', 'selected'], false], ['-', 0.62, ['*', ['number', ['get', 'selectedPulse'], 0], 0.42]],
                    ['boolean', ['get', 'hovered'], false], 0.38,
                    ['boolean', ['get', 'dimmed'], false], 0.08,
                    0.24
                  ]
                ],
                'circle-radius-transition': { duration: 300, delay: 0 },
                'circle-color-transition': { duration: 360, delay: 0 },
                'circle-opacity-transition': { duration: 220, delay: 0 },
                'circle-blur': 0.85
              }
            });
          }
          if (!map.getLayer('weather-halo')) {
            map.addLayer({
              id: 'weather-halo', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['*', ['number', ['get', 'visibleScale'], 1], ['+', 7, ['*', ['number', ['get', 'selectedPulse'], 0], 5]]],
                'circle-color': ['get', 'color'],
                'circle-opacity': ['*',
                  ['number', ['get', 'visibleScale'], 1],
                  ['case',
                    ['boolean', ['get', 'selected'], false], 0.42,
                    ['boolean', ['get', 'hovered'], false], 0.24,
                    ['boolean', ['get', 'dimmed'], false], 0.04,
                    0.14
                  ]
                ],
                'circle-radius-transition': { duration: 300, delay: 0 },
                'circle-color-transition': { duration: 360, delay: 0 },
                'circle-opacity-transition': { duration: 220, delay: 0 },
                'circle-blur': 0.45
              }
            });
          }
          if (!map.getLayer('weather-points')) {
            map.addLayer({
              id: 'weather-points', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['*', ['number', ['get', 'visibleScale'], 1], ['+', 4.5, ['*', ['number', ['get', 'scale'], 0], 2.5]]],
                'circle-color': ['get', 'color'],
                'circle-opacity': ['*',
                  ['number', ['get', 'visibleScale'], 1],
                  ['case',
                    ['boolean', ['get', 'selected'], false], 1,
                    ['boolean', ['get', 'dimmed'], false], 0.28,
                    1
                  ]
                ],
                'circle-radius-transition': { duration: 300, delay: 0 },
                'circle-color-transition': { duration: 360, delay: 0 },
                'circle-opacity-transition': { duration: 220, delay: 0 }
              }
            });
          }
        }

        function emptyCollection() {
          return { type: 'FeatureCollection', features: [] };
        }

        function collectionFromPayload(payload) {
          const selectedID = payload.selectedID || '';
          const hasSelection = selectedID !== '';
          const hoverEnabled = payload.allowsMarkerHover !== false;
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
                hidden: !!item.hidden,
                scale: markerScales[item.id] ?? 0,
                visibleScale: markerVisibilityScales[item.id] ?? (item.hidden ? 0 : 1),
                selectedPulse: item.id === selectedID ? selectedPulse : 0,
                selected: item.id === selectedID,
                hovered: hoverEnabled && item.id === hoveredMarkerID,
                dimmed: hasSelection && item.id !== selectedID
              },
              geometry: { type: 'Point', coordinates: [item.longitude, item.latitude] }
            }))
          };
        }

        function markerTargetScale(id) {
          const hoverEnabled = pendingPayload?.allowsMarkerHover !== false;
          return (id && id === selectedMarkerID) ? 1.35 : (hoverEnabled && id && id === hoveredMarkerID ? 1 : 0);
        }

        function markerVisibilityTarget(item) {
          return item.hidden ? 0 : 1;
        }

        function renderWeatherSource() {
          const source = map?.getSource('weather');
          if (source && pendingPayload) source.setData(collectionFromPayload(pendingPayload));
        }

        function animateMarkerScales() {
          if (markerScaleAnimationFrame) return;
          function step() {
            let needsNextFrame = false;
            (pendingPayload?.features || []).forEach(item => {
              const current = markerScales[item.id] ?? 0;
              const target = markerTargetScale(item.id);
              const next = current + (target - current) * 0.26;
              markerScales[item.id] = Math.abs(next - target) < 0.01 ? target : next;
              if (markerScales[item.id] !== target) needsNextFrame = true;

              const currentVisibility = markerVisibilityScales[item.id] ?? (item.hidden ? 0 : 1);
              const visibilityTarget = markerVisibilityTarget(item);
              const nextVisibility = currentVisibility + (visibilityTarget - currentVisibility) * 0.22;
              markerVisibilityScales[item.id] = Math.abs(nextVisibility - visibilityTarget) < 0.01 ? visibilityTarget : nextVisibility;
              if (markerVisibilityScales[item.id] !== visibilityTarget) needsNextFrame = true;
            });
            renderWeatherSource();
            markerScaleAnimationFrame = needsNextFrame ? requestAnimationFrame(step) : null;
          }
          markerScaleAnimationFrame = requestAnimationFrame(step);
        }

        function updateMarkerScaleTargets() {
          (pendingPayload?.features || []).forEach(item => {
            if (markerScales[item.id] === undefined) markerScales[item.id] = 0;
            if (markerVisibilityScales[item.id] === undefined) markerVisibilityScales[item.id] = item.hidden ? 0 : 1;
          });
          animateMarkerScales();
        }

        function updateSelectedPulse() {
          if (!selectedMarkerID) {
            if (selectedPulseAnimationFrame) cancelAnimationFrame(selectedPulseAnimationFrame);
            selectedPulseAnimationFrame = null;
            selectedPulse = 0;
            renderWeatherSource();
            return;
          }
          if (selectedPulseAnimationFrame) return;
          const start = performance.now();
          function step(now) {
            selectedPulse = (Math.sin((now - start) / 520) + 1) / 2;
            renderWeatherSource();
            selectedPulseAnimationFrame = selectedMarkerID ? requestAnimationFrame(step) : null;
          }
          selectedPulseAnimationFrame = requestAnimationFrame(step);
        }

        function updateSource(payload) {
          pendingPayload = payload;
          if (payload?.allowsMarkerHover === false) {
            hoveredMarkerID = '';
            hoveredMarkerPoint = null;
            document.getElementById('hover-label')?.classList.remove('visible');
            if (!(payload?.selectedID || '')) {
              Object.keys(markerScales).forEach(id => { markerScales[id] = 0; });
            }
          }
          selectedMarkerID = payload?.selectedID || '';
          document.body.classList.toggle('focus-selected', !!selectedMarkerID);
          ensureLayers();
          updateMarkerScaleTargets();
          updateSelectedPulse();
          renderWeatherSource();
        }

        window.updateWeatherData = function(payload) {
          if (!loaded) { pendingPayload = payload; return; }
          updateSource(payload);
        };

        window.setWeatherMapCameraProfile = function(profile) {
          cameraProfile = cameraProfiles[profile] ? profile : 'desktop';
          applyCameraProfileClass();
        };

        window.fitWeatherData = function(leadingPadding = 0) {
          if (!pendingPayload || !pendingPayload.features || pendingPayload.features.length === 0) return;
          const bounds = new maplibregl.LngLatBounds();
          pendingPayload.features.forEach(item => bounds.extend([item.longitude, item.latitude]));
          if (!bounds.isEmpty()) {
            const camera = activeCameraProfile();
            const padding = {
              top: camera.fitPadding.top,
              right: camera.fitPadding.right,
              bottom: camera.fitPadding.bottom,
              left: camera.fitPadding.left + (camera.useLeadingOffset ? leadingPadding : 0)
            };
            map.fitBounds(bounds, {
              padding,
              duration: 550,
              maxZoom: camera.fitMaxZoom
            });
          }
        };

        window.flyToCity = function(id, leadingPadding = 0) {
          const item = pendingPayload?.features?.find(feature => feature.id === id);
          const camera = activeCameraProfile();
          if (item) map.flyTo({
            center: [item.longitude, item.latitude],
            zoom: Math.max(map.getZoom(), camera.cityZoom),
            duration: 550,
            offset: [camera.useLeadingOffset ? leadingPadding / 2 : 0, 0]
          });
        };

        window.setMapStyleMode = async function(mode) {
          currentStyleMode = mode;
          document.body.classList.toggle('dark-map', mode === 'dark');
          baseStylePreferencesApplied = false;
          if (map) map.setStyle(await cleanedStyle(mode));
          setTimeout(() => {
            ensureLayers();
            renderWeatherSource();
          }, 0);
        };

        window.weatherMapZoomIn = function() {
          if (map) map.zoomIn({ duration: 220 });
        };

        window.weatherMapZoomOut = function() {
          if (map) map.zoomOut({ duration: 220 });
        };

        window.weatherMapStep = function(key) {
          if (!map) return;
          const step = 80;
          if (key === 'w') map.panBy([0, -step], { duration: 180 });
          if (key === 'a') map.panBy([-step, 0], { duration: 180 });
          if (key === 's') map.panBy([0, step], { duration: 180 });
          if (key === 'd') map.panBy([step, 0], { duration: 180 });
        };

        window.weatherMapKeyboardZoom = function(key) {
          if (!map) return;
          if (key === 'c') map.zoomTo(map.getZoom() + 0.6, { duration: 180 });
          if (key === 'v') map.zoomTo(map.getZoom() - 0.6, { duration: 180 });
        };

        function markerScreenPoint(feature, fallbackPoint) {
          const coordinates = feature?.geometry?.coordinates;
          return coordinates ? map.project(coordinates) : fallbackPoint;
        }

        function nearestMarkerFeature(features, point) {
          if (!features || !features.length) return null;
          let best = null;
          let bestDistance = Infinity;
          const seen = new Set();
          features.forEach(feature => {
            const id = feature?.properties?.id;
            if (!id || seen.has(id)) return;
            seen.add(id);
            const markerPoint = markerScreenPoint(feature, point);
            const dx = markerPoint.x - point.x;
            const dy = markerPoint.y - point.y;
            const distance = dx * dx + dy * dy;
            if (distance < bestDistance) {
              bestDistance = distance;
              best = feature;
            }
          });
          return best;
        }

        function markerFeatureAtPoint(point, radius = 11) {
          const hitBox = [
            [point.x - radius, point.y - radius],
            [point.x + radius, point.y + radius]
          ];
          const features = map.queryRenderedFeatures(hitBox, {
            layers: ['weather-hit', 'weather-points', 'weather-halo', 'weather-glow']
          });
          return nearestMarkerFeature(features, point);
        }

        function openHoveredMarkerFromPoint(point) {
          if (!hoveredMarkerID || !hoveredMarkerPoint) return false;
          post({ type: 'markerTap', id: hoveredMarkerID, x: hoveredMarkerPoint.x, y: hoveredMarkerPoint.y });
          return true;
        }

        function updateHoveredMarkerLabel(id, point) {
          if (pendingPayload?.allowsMarkerHover === false) {
            document.getElementById('hover-label')?.classList.remove('visible');
            return;
          }
          const feature = pendingPayload?.features?.find(item => item.id === id);
          const label = document.getElementById('hover-label');
          if (!label || !feature || !point) return;
          if (id && id === selectedMarkerID) {
            label.classList.remove('visible');
            return;
          }
          const clipped = point.x < 18
            || point.y < 18
            || point.x > window.innerWidth - 18
            || point.y > window.innerHeight - 18;
          if (clipped || !feature.name) {
            label.classList.remove('visible');
          } else {
            label.textContent = feature.name || '';
            label.style.left = `${point.x}px`;
            label.style.top = `${point.y}px`;
            label.classList.add('visible');
          }
        }

        function refreshHoveredMarker(id, point) {
          if (pendingPayload?.allowsMarkerHover === false) return;
          updateHoveredMarkerLabel(id, point);
          if (hoveredMarkerID === id) {
            hoveredMarkerPoint = point;
          } else {
            hoveredMarkerID = id;
            hoveredMarkerPoint = point;
            if (pendingPayload) updateSource(pendingPayload);
          }
        }

        function updateHoveredMarkerPosition() {
          if (!hoveredMarkerID || !pendingPayload) return;
          const feature = pendingPayload.features?.find(item => item.id === hoveredMarkerID);
          if (!feature) {
            clearHoveredMarker();
            return;
          }
          const point = map.project([feature.longitude, feature.latitude]);
          hoveredMarkerPoint = point;
          updateHoveredMarkerLabel(hoveredMarkerID, point);
        }

        function endCommandHoverCard() {
          if (!commandHoverCardID) return;
          commandHoverCardID = '';
          post({ type: 'markerCommandHoverEnd' });
        }

        function updateCommandHoverCard() {
          if (!commandPressed || !hoveredMarkerID || !hoveredMarkerPoint) {
            endCommandHoverCard();
            return;
          }
          if (commandHoverCardID === hoveredMarkerID) return;
          commandHoverCardID = hoveredMarkerID;
          post({
            type: 'markerCommandHover',
            id: hoveredMarkerID,
            x: hoveredMarkerPoint.x,
            y: hoveredMarkerPoint.y
          });
        }

        function clearHoveredMarker() {
          if (!hoveredMarkerID) return;
          hoveredMarkerID = '';
          hoveredMarkerPoint = null;
          document.getElementById('hover-label')?.classList.remove('visible');
          if (pendingPayload) updateSource(pendingPayload);
          endCommandHoverCard();
        }

        function stopPinchInertia() {
          if (pinchAnimationFrame) cancelAnimationFrame(pinchAnimationFrame);
          pinchAnimationFrame = null;
          pinchVelocity = 0;
        }

        function startPinchInertia(point) {
          if (pinchAnimationFrame) cancelAnimationFrame(pinchAnimationFrame);
          function step() {
            pinchVelocity *= 0.88;
            if (Math.abs(pinchVelocity) < 0.001) {
              pinchAnimationFrame = null;
              pinchVelocity = 0;
              return;
            }
            map.zoomTo(map.getZoom() + pinchVelocity, {
              duration: 0,
              around: map.unproject(point)
            });
            pinchAnimationFrame = requestAnimationFrame(step);
          }
          pinchAnimationFrame = requestAnimationFrame(step);
        }

        async function init() {
          applyCameraProfileClass();
          const camera = activeCameraProfile();
          map = new maplibregl.Map({
            container: 'map',
            style: await cleanedStyle(currentStyleMode),
            preserveDrawingBuffer: false,
            center: camera.initialCenter,
            zoom: camera.initialZoom,
            minZoom: 1,
            maxZoom: 12,
            attributionControl: false
          });
          map.dragRotate.disable();
          map.touchZoomRotate.disableRotation();
          map.scrollZoom.disable();
          map.getCanvas().addEventListener('wheel', event => {
            event.preventDefault();
            event.stopImmediatePropagation();
            const point = new maplibregl.Point(event.offsetX, event.offsetY);
            if (event.ctrlKey) {
              const delta = -event.deltaY / 72;
              pinchVelocity = Math.max(-0.62, Math.min(0.62, delta));
              map.zoomTo(map.getZoom() + pinchVelocity, {
                duration: 0,
                around: map.unproject(point)
              });
              startPinchInertia(point);
            } else {
              stopPinchInertia();
              map.panBy([event.deltaX, event.deltaY], { duration: 0 });
            }
          }, { capture: true, passive: false });
          map.getCanvas().addEventListener('mousedown', event => {
            if (event.button !== 0) return;
            leftMouseDown = {
              x: event.offsetX,
              y: event.offsetY,
              time: Date.now(),
              hoveredID: hoveredMarkerID || '',
              hoveredPoint: hoveredMarkerPoint ? { x: hoveredMarkerPoint.x, y: hoveredMarkerPoint.y } : null
            };
          }, { capture: true, passive: true });
          map.getCanvas().addEventListener('mouseup', event => {
            if (event.button !== 0) return;
            const point = new maplibregl.Point(event.offsetX, event.offsetY);
            const down = leftMouseDown;
            leftMouseDown = null;
            if (!down) return;
            const dx = event.offsetX - down.x;
            const dy = event.offsetY - down.y;
            const movement = Math.sqrt(dx * dx + dy * dy);
            const elapsed = Date.now() - down.time;
            if (movement <= 12 && elapsed < 1000 && (hoveredMarkerID || down.hoveredID)) {
              const id = hoveredMarkerID || down.hoveredID;
              const markerPoint = hoveredMarkerID && hoveredMarkerPoint
                ? hoveredMarkerPoint
                : down.hoveredPoint;
              if (id && markerPoint) {
                post({ type: 'markerTap', id, x: markerPoint.x, y: markerPoint.y });
                event.preventDefault();
                event.stopImmediatePropagation();
              }
            }
          }, { capture: true, passive: false });
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
            if (hoveredMarkerID && hoveredMarkerPoint) {
              post({ type: 'markerTap', id: hoveredMarkerID, x: hoveredMarkerPoint.x, y: hoveredMarkerPoint.y });
              return;
            }
            if (event.originalEvent?._weatherMarkerHandled) return;
            const feature = markerFeatureAtPoint(event.point);
            if (feature?.properties?.id) {
              event.originalEvent._weatherMarkerHandled = true;
              const markerPoint = markerScreenPoint(feature, event.point);
              post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y });
            } else {
              const lngLat = event.lngLat;
              post({ type: 'mapBackgroundClick', lat: lngLat.lat, lng: lngLat.lng, x: event.point.x, y: event.point.y });
            }
          });
          map.on('click', 'weather-hit', event => {
            const feature = nearestMarkerFeature(event.features, event.point);
            if (!feature?.properties?.id) return;
            event.originalEvent._weatherMarkerHandled = true;
            const markerPoint = markerScreenPoint(feature, event.point);
            post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y });
          });
          map.on('contextmenu', event => {
            event.preventDefault();
          });
          map.on('mousemove', 'weather-hit', event => {
            if (pendingPayload?.allowsMarkerHover === false) return;
            const feature = nearestMarkerFeature(event.features, event.point);
            if (!feature?.properties?.id) return;
            commandPressed = !!event.originalEvent?.metaKey;
            const markerPoint = markerScreenPoint(feature, event.point);
            refreshHoveredMarker(feature.properties.id, markerPoint);
            updateCommandHoverCard();
          });
          map.on('mouseenter', 'weather-hit', () => { map.getCanvas().style.cursor = 'default'; });
          map.on('mouseleave', 'weather-hit', () => {
            map.getCanvas().style.cursor = 'default';
            clearHoveredMarker();
          });
          map.on('move', () => {
            updateHoveredMarkerPosition();
            const now = Date.now();
            if (now - lastMovePost < 120) return;
            lastMovePost = now;
            const center = map.getCenter();
            post({ type: 'cameraMove', lat: center.lat, lng: center.lng });
          });
          const pressedPanKeys = new Set();
          const pressedZoomKeys = new Set();
          let panAnimationFrame = null;

          function panLoop() {
            if (!pressedPanKeys.size && !pressedZoomKeys.size) {
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
            if (pressedZoomKeys.has('c')) map.zoomTo(map.getZoom() + 0.035, { duration: 0 });
            if (pressedZoomKeys.has('v')) map.zoomTo(map.getZoom() - 0.035, { duration: 0 });
            panAnimationFrame = requestAnimationFrame(panLoop);
          }

          function startPanLoop() {
            if (!panAnimationFrame) panAnimationFrame = requestAnimationFrame(panLoop);
          }

          window.addEventListener('keydown', event => {
            const key = event.key.toLowerCase();
            if (event.metaKey || key === 'meta') {
              commandPressed = true;
              updateCommandHoverCard();
            }
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
            if (['c', 'v'].includes(key)) {
              event.preventDefault();
              pressedZoomKeys.add(key);
              startPanLoop();
            }
          });
          window.addEventListener('keyup', event => {
            const key = event.key.toLowerCase();
            if (!event.metaKey || key === 'meta') {
              commandPressed = false;
              endCommandHoverCard();
            }
            pressedPanKeys.delete(key);
            pressedZoomKeys.delete(key);
          });
          window.addEventListener('blur', () => {
            pressedPanKeys.clear();
            pressedZoomKeys.clear();
            commandPressed = false;
            endCommandHoverCard();
          });
        }

        if (window.maplibregl) init().catch(error => console.error('Map init failed', error));
      </script>
    </body>
    </html>
    """
}

enum MapCameraProfile: String {
    case desktop
    case mobile
}

private struct MapLibreWeatherFeature: Codable {
    let id: String
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    let label: String
    let color: String
    let hidden: Bool
}
