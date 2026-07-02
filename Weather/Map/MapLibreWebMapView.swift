//
//  MapLibreWebMapView.swift
//  Weather
//
//  Purpose: Renders the OpenStreetMap/MapLibre web map and bridges map events back to SwiftUI.
//

import SwiftUI
import WebKit
import CoreLocation
import UIKit

// MARK: - MapLibre Web Implementation

struct MapLibreWeatherFeature: Codable {
    let id: String
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    let label: String
    let color: String
    let hidden: Bool
}

struct MapLibreFitCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

struct MapLibreWebMapView: UIViewRepresentable {
    let cities: [CityWeather]
    let fitCities: [City]
    let selectedDayOffset: Int
    var overlayMode: String = "weather"
    let filterSunny: Bool
    var markerReloadID: Int = 0
    var markerSizeScale: Double = 1
    var showsMarkerHoverLabels: Bool = true
    @Binding var tappedCity: CityWeather?
    @Binding var recenterRequest: MapRecenterRequest?
    var centerOnCity: CityWeather?
    var leadingFitPadding: Double = 0
    var focusSelectedMarker: Bool = true
    var allowsMarkerHover: Bool = true
    var cameraProfile: MapCameraProfile = .desktop
    var onMarkerTap: (CityWeather, CGPoint?) -> Void
    var onMapClick: ((CLLocationCoordinate2D, CGPoint?) -> Void)? = nil
    var onCameraMove: ((CLLocationCoordinate2D) -> Void)? = nil
    var onMapGestureStart: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.defaultRawValue

    // MARK: Platform Web View Lifecycle

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        dismantleWebView(uiView, coordinator: coordinator)
    }

    // MARK: Web View Setup and Updates

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "mapEvent")
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.dataDetectorTypes = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsLinkPreview = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = platformMapBackgroundColor
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

    private func updateWebView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.webView = webView
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = platformMapBackgroundColor
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = platformMapBackgroundColor
        }
        context.coordinator.pushStateIfReady()
    }

    private var platformMapBackgroundColor: UIColor {
        colorScheme == .dark
            ? UIColor(red: 0x1A / 255.0, green: 0x1B / 255.0, blue: 0x2E / 255.0, alpha: 1)
            : UIColor(red: 0xF4 / 255.0, green: 0xF1 / 255.0, blue: 0xEB / 255.0, alpha: 1)
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
        private var lastMarkerReloadID = 0
        private var lastCenteredCityID: UUID?
        private var observers: [NSObjectProtocol] = []

        init(parent: MapLibreWebMapView) {
            self.parent = parent
            super.init()
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                let styleKey = self.parent.colorScheme == .dark ? "dark" : "bright"
                self.evaluate("window.weatherMapReloadBaseMapAfterActivation?.(\(Self.jsString(styleKey)));")
                self.pushStateIfReady(force: true)
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
                if parent.cameraProfile == .mobile,
                   let tapX = body["tapX"] as? Double,
                   let tapY = body["tapY"] as? Double {
                    point = CGPoint(x: tapX, y: tapY)
                } else if let x = body["x"] as? Double, let y = body["y"] as? Double {
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
            case "cameraMove":
                guard let lat = body["lat"] as? Double,
                      let lng = body["lng"] as? Double else { return }
                parent.onCameraMove?(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            case "mapGestureStart":
                parent.onMapGestureStart?()
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
            let fitCoordinates = parent.makeFitCoordinates()
            guard let data = try? JSONEncoder().encode(features),
                  let json = String(data: data, encoding: .utf8),
                  let fitData = try? JSONEncoder().encode(fitCoordinates),
                  let fitJSON = String(data: fitData, encoding: .utf8) else { return }
            let selectedID = parent.focusSelectedMarker ? (parent.tappedCity?.id.uuidString ?? "") : ""
            let payload = "{features:\(json),fitCoordinates:\(fitJSON),selectedID:\(Self.jsString(selectedID)),allowsMarkerHover:\(parent.allowsMarkerHover ? "true" : "false"),showsMarkerHoverLabels:\(parent.showsMarkerHoverLabels ? "true" : "false"),markerSizeScale:\(parent.markerSizeScale)}"

            let shouldReloadMarkers = parent.markerReloadID != lastMarkerReloadID
            if shouldReloadMarkers {
                lastMarkerReloadID = parent.markerReloadID
            }
            if force || shouldReloadMarkers || payload != lastPayload {
                lastPayload = payload
                evaluate("window.updateWeatherData(\(payload));")
            }

            if let recenterRequest = parent.recenterRequest {
                let useListCoordinates = recenterRequest == .listCoordinates ? "true" : "false"
                evaluate("window.fitWeatherData(\(parent.leadingFitPadding), \(useListCoordinates));")
                DispatchQueue.main.async {
                    self.parent.recenterRequest = nil
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

    // MARK: Marker Payload

    private func makeFitCoordinates() -> [MapLibreFitCoordinate] {
        fitCities.map { city in
            MapLibreFitCoordinate(latitude: city.latitude, longitude: city.longitude)
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
                name: cityWeather.city.localizedName(locale: locale),
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

    // MARK: Marker Colors

    private func markerColor(for cityWeather: CityWeather, forecast: DailyForecast) -> String {
        let isNow = selectedDayOffset == -1
        if overlayMode == "temperature" {
            return temperatureColor(isNow ? cityWeather.temperature : forecast.dailyHigh)
        }
        if overlayMode == "cloudCover" {
            let value = isNow ? cityWeather.currentCloudCover : forecast.cloudCover
            return blendHex(from: dotRainHex, to: dotCloudyHex, amount: value ?? 0.5)
        }
        if overlayMode == "precipitation" {
            let chance: Double
            if isNow {
                chance = [.rain, .drizzle, .snow].contains(cityWeather.condition) ? 1 : 0
            } else {
                chance = forecast.precipitationChance ?? 0.5
            }
            return blendHex(from: 0xFFFFFF, to: dotDrizzleHex, amount: chance)
        }
        if overlayMode == "windSpeed" {
            let windSpeed = (isNow ? cityWeather.currentWindSpeed : forecast.windSpeed) ?? 0
            let wind = min(1, windSpeed / 100)
            return blendHex(from: 0xFFFFFF, to: saturatedPartlySunnyHex, amount: wind)
        }
        if overlayMode == "uvIndex" {
            let uv = min(1, Double((isNow ? cityWeather.currentUVIndex : forecast.uvIndex) ?? 0) / 11)
            return blendHex(from: 0xFFFFFF, to: destructiveHex, amount: uv)
        }
        if overlayMode == "humidity" {
            return blendHex(from: 0xFFFFFF, to: dotDrizzleHex, amount: (isNow ? cityWeather.currentHumidity : forecast.maxHumidity) ?? 0.5)
        }
        if overlayMode == "visibility" {
            let visibility = min(1, ((isNow ? cityWeather.currentVisibility : forecast.maxVisibility) ?? 15) / 30)
            return blendHex(from: 0xFFFFFF, to: dotRainHex, amount: visibility)
        }
        let condition = isNow ? cityWeather.condition : forecast.condition
        return color(for: condition, icon: isNow ? cityWeather.weatherIcon : forecast.weatherIcon)
    }

    private func color(for condition: AppWeatherCondition, icon: String) -> String {
        if icon.contains("moon") { return "#A285B7" }
        switch condition {
        case .clear: return "#FF8A65"
        case .partlySunny: return "#EEB368"
        case .partlyCloudy: return colorScheme == .dark ? "#D3E3EC" : "#B8C7D0"
        case .cloudy: return colorScheme == .dark ? "#D3E3EC" : "#B8C7D0"
        case .rain: return "#4D70D4"
        case .drizzle: return "#65ABE3"
        case .snow: return colorScheme == .dark ? "#D3E3EC" : "#B8C7D0"
        case .fog: return "#D3E3EC"
        case .wind: return colorScheme == .dark ? "#D3E3EC" : "#B8C7D0"
        }
    }

    private func temperatureColor(_ tempC: Double) -> String {
        if tempC <= 0 {
            return blendHex(from: dotRainHex, to: dotDrizzleHex, amount: max(0, min(1, (tempC + 20) / 20)))
        }
        if tempC <= 10 {
            return blendHex(from: dotDrizzleHex, to: dotCloudyHex, amount: max(0, min(1, tempC / 10)))
        }
        if tempC <= 20 {
            return blendHex(from: dotCloudyHex, to: saturatedPartlySunnyHex, amount: max(0, min(1, (tempC - 10) / 10)))
        }
        return blendHex(from: saturatedPartlySunnyHex, to: destructiveHex, amount: max(0, min(1, (tempC - 20) / 20)))
    }

    private var dotCloudyHex: Int {
        colorScheme == .dark ? 0xD3E3EC : 0xB8C7D0
    }

    private var dotRainHex: Int {
        0x4D70D4
    }

    private var dotDrizzleHex: Int {
        0x65ABE3
    }

    private var dotPartlyCloudyHex: Int {
        colorScheme == .dark ? 0xF4DC85 : 0xEEB368
    }

    private var destructiveHex: Int {
        0xC94949
    }

    private var saturatedPartlySunnyHex: Int {
        blendInt(from: dotPartlyCloudyHex, to: 0xFF8A65, amount: 0.18)
    }

    private func blendHex(from: Int, to: Int, amount: Double) -> String {
        let color = blendInt(from: from, to: to, amount: amount)
        return String(format: "#%02X%02X%02X", (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF)
    }

    private func blendInt(from: Int, to: Int, amount: Double) -> Int {
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
        return (r << 16) | (g << 8) | b
    }

    private static let html = """
    <!doctype html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
      <link rel="stylesheet" href="https://unpkg.com/maplibre-gl/dist/maplibre-gl.css">
      <script src="https://unpkg.com/maplibre-gl/dist/maplibre-gl.js"></script>
      <style>
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; min-height: 100%; overflow: hidden; background: #FFFFFF; }
        body { -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; position: fixed; inset: 0; }
        #map { position: fixed; inset: 0; width: 100vw; height: 100vh; height: 100dvh; background: #FFFFFF; }
        @media (prefers-color-scheme: dark) {
          html, body, #map { background: #2E2961; }
        }
        #window-drag-blur {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          height: 42px;
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
          font: 600 12px system-ui, "SF Pro Text", "Helvetica Neue", sans-serif;
          color: #444444;
          background: rgba(248, 244, 241, 0.9);
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
          color: #E7E7E8;
          background: rgba(46, 41, 97, 0.9);
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
        var currentStyleMode = window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'bright';
        var lastMovePost = 0;
        var hoveredMarkerID = '';
        var hoveredMarkerPoint = null;
        var selectedMarkerID = '';
        var markerScales = {};
        var markerVisibilityScales = {};
        var markerScaleAnimationFrame = null;
        var selectedPulseAnimationFrame = null;
        var selectedPulse = 0;
        var pinchVelocity = 0;
        var pinchAnimationFrame = null;
        var mapResizeObserver = null;
        var pendingFitRequest = null;
        var initStarted = false;
        var baseStylePreferencesApplied = false;
        var leftMouseDown = null;
        var touchDown = null;
        var suppressNextClickUntil = 0;
        const markerHitRadius = 16;
        var cameraProfile = 'mobile';
        const cameraProfiles = {
          desktop: {
            initialCenter: [0, 20],
            initialZoom: 1.45,
            fitPadding: { top: 180, right: 180, bottom: 180, left: 180 },
            fitMaxZoom: 4.2,
            cityZoom: 5,
            useLeadingOffset: true
          },
          tablet: {
            initialCenter: [0, 12],
            initialZoom: 1.15,
            fitPadding: { top: 116, right: 70, bottom: 238, left: 70 },
            fitMaxZoom: 3.65,
            cityZoom: 4.35,
            useLeadingOffset: true
          },
          mobile: {
            initialCenter: [0, 12],
            initialZoom: 1.15,
            fitPadding: { top: 104, right: 52, bottom: 228, left: 52 },
            fitMaxZoom: 4.2,
            cityZoom: 4.35,
            useLeadingOffset: true
          },
          discovery: {
            initialCenter: [0, 16],
            initialZoom: 0.95,
            fitPadding: { top: 104, right: 48, bottom: 430, left: 48 },
            fitMaxZoom: 3.45,
            cityZoom: 4.0,
            useLeadingOffset: false
          },
          preview: {
            initialCenter: [10, 46],
            initialZoom: 2.4,
            fitPadding: { top: 34, right: 34, bottom: 34, left: 34 },
            fitMaxZoom: 4.8,
            cityZoom: 4.4,
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

        ['contextmenu', 'selectstart', 'copy', 'cut', 'paste', 'dragstart'].forEach(eventName => {
          document.addEventListener(eventName, event => event.preventDefault(), { passive: false });
        });

        function postMapGestureStart() {
          post({ type: 'mapGestureStart' });
        }

        function mapElementHasUsableSize() {
          const element = document.getElementById('map');
          const rect = element?.getBoundingClientRect();
          return !!rect && rect.width >= 64 && rect.height >= 64;
        }

        function activeCameraProfile() {
          return cameraProfiles[cameraProfile] || cameraProfiles.mobile;
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
            ? { ocean: '#2E2961', land: '#423D74', subtleLand: '#423D74', road: '#56508B' }
            : { ocean: '#FFFFFF', land: '#F8F4F1', subtleLand: '#F8F4F1', road: '#E6DDD7' };
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

        function isBoundaryLikeLayer(combined) {
          return combined.includes('boundary')
            || combined.includes('admin')
            || combined.includes('border')
            || combined.includes('disputed');
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

          if (layer.type === 'line' && isBoundaryLikeLayer(combined)) {
            layer.layout = layer.layout || {};
            layer.layout.visibility = 'none';
            layer.paint['line-color'] = currentStyleMode === 'dark' ? '#171322' : '#5C526E';
            layer.paint['line-opacity'] = currentStyleMode === 'dark' ? 0.48 : 0.28;
            layer.paint['line-width'] = [
              'interpolate',
              ['linear'],
              ['zoom'],
              0, 0.35,
              3, 0.65,
              6, 1.05
            ];
            return;
          }

          if (layer.type === 'line' && isRoadLikeLayer(combined)) {
            layer.layout = layer.layout || {};
            layer.layout.visibility = 'none';
          }

          if (layer.type === 'symbol') {
            layer.layout = layer.layout || {};
            layer.layout.visibility = 'none';
          }
        }

        function shouldHideBaseLayer(layer) {
          const combined = layerSignature(layer);

          if (layer.type === 'line') {
            return isRoadLikeLayer(combined)
              || combined.includes('ferry')
              || combined.includes('marine')
              || combined.includes('navigation')
              || combined.includes('shipping');
          }

          if (layer.type === 'symbol') {
            return true;
          }

          return false;
        }

        async function cleanedStyle(mode) {
          const response = await fetch(styleURL(mode), { cache: 'reload' });
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
                'circle-radius': ['*', ['number', ['get', 'markerSizeScale'], 1], ['*', ['number', ['get', 'visibleScale'], 1], markerHitRadius]],
                'circle-color': 'rgba(0,0,0,0.01)',
                'circle-opacity': 0.01
              }
            });
          }
          if (!map.getLayer('weather-glow')) {
            map.addLayer({
              id: 'weather-glow', type: 'circle', source: 'weather',
              paint: {
                'circle-radius': ['*', ['number', ['get', 'markerSizeScale'], 1], ['*', ['number', ['get', 'visibleScale'], 1], ['+', 13, ['*', ['number', ['get', 'selectedPulse'], 0], 13]]]],
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
                'circle-radius': ['*', ['number', ['get', 'markerSizeScale'], 1], ['*', ['number', ['get', 'visibleScale'], 1], ['+', 7, ['*', ['number', ['get', 'selectedPulse'], 0], 5]]]],
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
                'circle-radius': ['*', ['number', ['get', 'markerSizeScale'], 1], ['*', ['number', ['get', 'visibleScale'], 1], ['+', 4.5, ['*', ['number', ['get', 'scale'], 0], 2.5]]]],
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
                dimmed: hasSelection && item.id !== selectedID,
                markerSizeScale: payload.markerSizeScale || 1
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
          if (payload?.allowsMarkerHover === false || payload?.showsMarkerHoverLabels === false) {
            hoveredMarkerID = '';
            hoveredMarkerPoint = null;
            document.getElementById('hover-label')?.classList.remove('visible');
          }
          selectedMarkerID = payload?.selectedID || '';
          document.body.classList.toggle('focus-selected', !!selectedMarkerID);
          ensureLayers();
          updateMarkerScaleTargets();
          updateSelectedPulse();
          renderWeatherSource();
          if (pendingFitRequest && mapElementHasUsableSize()) {
            const request = pendingFitRequest;
            window.fitWeatherData(request.leadingPadding, request.useFitCoordinates);
          }
        }

        window.updateWeatherData = function(payload) {
          if (!loaded) { pendingPayload = payload; return; }
          updateSource(payload);
        };

        window.setWeatherMapCameraProfile = function(profile) {
          cameraProfile = cameraProfiles[profile] ? profile : 'mobile';
          applyCameraProfileClass();
        };

        window.fitWeatherData = function(leadingPadding = 0, useFitCoordinates = false) {
          pendingFitRequest = { leadingPadding, useFitCoordinates };
          if (!mapElementHasUsableSize()) return;
          if (!pendingPayload) return;
          const savedListCoordinates = pendingPayload.fitCoordinates || [];
          const fitItems = useFitCoordinates ? savedListCoordinates : (pendingPayload.features?.length ? pendingPayload.features : savedListCoordinates);
          if (!fitItems.length) return;
          const bounds = new maplibregl.LngLatBounds();
          fitItems.forEach(item => bounds.extend([item.longitude, item.latitude]));
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
            pendingFitRequest = null;
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
          if (!map) return;
          const restoreWeatherLayers = () => {
            baseStylePreferencesApplied = false;
            ensureLayers();
            if (pendingPayload) updateSource(pendingPayload);
            renderWeatherSource();
          };
          map.once('style.load', restoreWeatherLayers);
          map.setStyle(await cleanedStyle(mode));
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

        function markerFeatureAtPoint(point, radius = markerHitRadius) {
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
          const feature = markerFeatureAtPoint(point, markerHitRadius);
          if (!feature?.properties?.id) return false;
          const markerPoint = markerScreenPoint(feature, point);
          post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y, tapX: point.x, tapY: point.y });
          return true;
        }

        function updateHoveredMarkerLabel(id, point) {
          if (pendingPayload?.allowsMarkerHover === false || pendingPayload?.showsMarkerHoverLabels === false) {
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
          if (pendingPayload?.showsMarkerHoverLabels === false) {
            document.getElementById('hover-label')?.classList.remove('visible');
          } else {
            updateHoveredMarkerLabel(id, point);
          }
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

        function clearHoveredMarker() {
          if (!hoveredMarkerID) return;
          hoveredMarkerID = '';
          hoveredMarkerPoint = null;
          document.getElementById('hover-label')?.classList.remove('visible');
          if (pendingPayload) updateSource(pendingPayload);
        }

        function stopPinchInertia() {
          if (pinchAnimationFrame) cancelAnimationFrame(pinchAnimationFrame);
          pinchAnimationFrame = null;
          pinchVelocity = 0;
        }

        function resizeMapSoon() {
          if (!map) return;
          requestAnimationFrame(() => {
            map.resize();
            if (pendingFitRequest && mapElementHasUsableSize()) {
              const request = pendingFitRequest;
              window.fitWeatherData(request.leadingPadding, request.useFitCoordinates);
            }
            setTimeout(() => {
              map.resize();
              if (pendingFitRequest && mapElementHasUsableSize()) {
                const request = pendingFitRequest;
                window.fitWeatherData(request.leadingPadding, request.useFitCoordinates);
              }
            }, 120);
          });
        }

        window.weatherMapRefreshAfterActivation = function() {
          if (!map) {
            startMapWhenReady();
            return;
          }
          resizeMapSoon();
          ensureLayers();
          if (pendingPayload) updateSource(pendingPayload);
        };

        window.weatherMapReloadBaseMapAfterActivation = async function(mode = currentStyleMode) {
          if (!map) {
            startMapWhenReady();
            return;
          }

          currentStyleMode = mode;
          document.body.classList.toggle('dark-map', mode === 'dark');
          const cameraState = {
            center: map.getCenter(),
            zoom: map.getZoom(),
            bearing: map.getBearing(),
            pitch: map.getPitch()
          };

          resizeMapSoon();
          baseStylePreferencesApplied = false;
          try {
            map.once('style.load', () => {
              loaded = true;
              resizeMapSoon();
              ensureLayers();
              if (pendingPayload) updateSource(pendingPayload);
              try {
                map.jumpTo(cameraState);
              } catch (_) {}
            });
            map.setStyle(await cleanedStyle(mode));
          } catch (error) {
            console.error('Base map reload failed', error);
            resizeMapSoon();
            ensureLayers();
            if (pendingPayload) updateSource(pendingPayload);
          }
        };

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
          if (initStarted || map) return;
          if (!mapElementHasUsableSize()) {
            setTimeout(startMapWhenReady, 80);
            return;
          }
          initStarted = true;
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
            postMapGestureStart();
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
          map.getCanvas().addEventListener('touchstart', event => {
            if (event.touches.length !== 1) {
              touchDown = null;
              return;
            }
            const rect = map.getCanvas().getBoundingClientRect();
            const touch = event.touches[0];
            touchDown = {
              x: touch.clientX - rect.left,
              y: touch.clientY - rect.top,
              time: Date.now()
            };
          }, { capture: true, passive: true });
          map.getCanvas().addEventListener('touchend', event => {
            const down = touchDown;
            touchDown = null;
            if (!down || event.changedTouches.length !== 1) return;
            const rect = map.getCanvas().getBoundingClientRect();
            const touch = event.changedTouches[0];
            const point = new maplibregl.Point(touch.clientX - rect.left, touch.clientY - rect.top);
            const dx = point.x - down.x;
            const dy = point.y - down.y;
            const movement = Math.sqrt(dx * dx + dy * dy);
            const elapsed = Date.now() - down.time;
            if (movement > 16 || elapsed >= 800) {
              postMapGestureStart();
              return;
            }
            const feature = markerFeatureAtPoint(point, markerHitRadius);
            if (!feature?.properties?.id) return;
            const markerPoint = markerScreenPoint(feature, point);
            suppressNextClickUntil = Date.now() + 350;
            post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y, tapX: point.x, tapY: point.y });
            event.preventDefault();
            event.stopImmediatePropagation();
          }, { capture: true, passive: false });
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
            if (movement <= 12 && elapsed < 1000) {
              const feature = markerFeatureAtPoint(point, markerHitRadius);
              if (feature?.properties?.id) {
                const markerPoint = markerScreenPoint(feature, point);
                suppressNextClickUntil = Date.now() + 350;
                post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y, tapX: point.x, tapY: point.y });
                event.preventDefault();
                event.stopImmediatePropagation();
              }
            } else {
              postMapGestureStart();
            }
          }, { capture: true, passive: false });
          map.on('load', () => {
            loaded = true;
            resizeMapSoon();
            ensureLayers();
            if (pendingPayload) updateSource(pendingPayload);
            post({ type: 'ready' });
          });
          map.on('styledata', () => {
            if (!loaded) return;
            resizeMapSoon();
            ensureLayers();
            if (pendingPayload) updateSource(pendingPayload);
          });
          map.on('click', event => {
            if (Date.now() < suppressNextClickUntil) return;
            if (event.originalEvent?._weatherMarkerHandled) return;
            const feature = markerFeatureAtPoint(event.point);
            if (feature?.properties?.id) {
              event.originalEvent._weatherMarkerHandled = true;
              const markerPoint = markerScreenPoint(feature, event.point);
              post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y, tapX: event.point.x, tapY: event.point.y });
            } else {
              const lngLat = event.lngLat;
              post({ type: 'mapBackgroundClick', lat: lngLat.lat, lng: lngLat.lng, x: event.point.x, y: event.point.y });
            }
          });
          map.on('click', 'weather-hit', event => {
            if (Date.now() < suppressNextClickUntil) return;
            const feature = nearestMarkerFeature(event.features, event.point);
            if (!feature?.properties?.id) return;
            event.originalEvent._weatherMarkerHandled = true;
            const markerPoint = markerScreenPoint(feature, event.point);
            post({ type: 'markerTap', id: feature.properties.id, x: markerPoint.x, y: markerPoint.y, tapX: event.point.x, tapY: event.point.y });
          });
          map.on('contextmenu', event => {
            event.preventDefault();
          });
          map.on('mousemove', 'weather-hit', event => {
            if (pendingPayload?.allowsMarkerHover === false) return;
            const feature = nearestMarkerFeature(event.features, event.point);
            if (!feature?.properties?.id) return;
            const markerPoint = markerScreenPoint(feature, event.point);
            refreshHoveredMarker(feature.properties.id, markerPoint);
          });
          map.on('mouseenter', 'weather-hit', () => { map.getCanvas().style.cursor = 'default'; });
          map.on('mouseleave', 'weather-hit', () => {
            map.getCanvas().style.cursor = 'default';
            clearHoveredMarker();
          });
          window.addEventListener('resize', resizeMapSoon);
          if (window.ResizeObserver) {
            mapResizeObserver = new ResizeObserver(resizeMapSoon);
            mapResizeObserver.observe(document.getElementById('map'));
          }

          map.on('move', () => {
            updateHoveredMarkerPosition();
            const now = Date.now();
            if (now - lastMovePost < 120) return;
            lastMovePost = now;
            const center = map.getCenter();
            post({ type: 'cameraMove', lat: center.lat, lng: center.lng });
          });
        }

        function startMapWhenReady(attempt = 0) {
          if (window.maplibregl) {
            init().catch(error => {
              initStarted = false;
              console.error('Map init failed', error);
              if (attempt < 12) setTimeout(() => startMapWhenReady(attempt + 1), 250);
            });
            return;
          }
          if (attempt < 24) setTimeout(() => startMapWhenReady(attempt + 1), 250);
        }

        startMapWhenReady();
      </script>
    </body>
    </html>
    """
}
