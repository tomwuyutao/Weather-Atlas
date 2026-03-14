//
//  SVGMapView.swift
//  Weather
//
//  Custom map view that renders the world SVG with weather markers.
//

import SwiftUI

struct SVGMapView: View {
    let countries: [CountryPath]
    let cities: [CityWeather]
    let selectedDayOffset: Int
    let showCloudCover: Bool
    var overlayMode: String = "weather"
    let filterSunny: Bool
    let isPlaying: Bool
    let namespace: Namespace.ID
    
    @Binding var isZoomedOut: Bool
    @Binding var showingCityDetail: Bool
    @Binding var tappedCity: CityWeather?
    
    @Binding var mapScale: CGFloat
    @Binding var mapOffset: CGSize
    @Binding var mapLastScale: CGFloat
    @Binding var mapLastOffset: CGSize
    @Binding var mapHasInitialized: Bool
    
    var centerOnCity: CityWeather?
    @Binding var recenterOnAllCities: Bool
    
    private let maxScale: CGFloat = 60.0
    private let rubberBandMaxScale: CGFloat = 75.0
    private let citiesPadding: CGFloat = 1.4
    
    /// Computes the scale that fits all cities on screen
    private func citiesFitScale(viewSize: CGSize, baseScale: CGFloat) -> CGFloat {
        guard !cities.isEmpty else { return 10.0 }
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for city in cities {
            let p = GeoProjection.geoToSVG(latitude: city.city.latitude, longitude: city.city.longitude)
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        let spanX = maxX - minX, spanY = maxY - minY
        if spanX < 0.001 && spanY < 0.001 { return 10.0 }
        let scaleX = viewSize.width / (spanX * baseScale * citiesPadding)
        let scaleY = viewSize.height / (spanY * baseScale * citiesPadding)
        return min(scaleX, scaleY)
    }
    
    /// Computes the SVG center point of all cities
    private func citiesCenterSVG() -> CGPoint {
        guard !cities.isEmpty else { return GeoProjection.geoToSVG(latitude: 35.0, longitude: 105.0) }
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        for city in cities {
            let p = GeoProjection.geoToSVG(latitude: city.city.latitude, longitude: city.city.longitude)
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
    }
    
    // Magnification samples used for per-frame rate limiting
    @State private var magnificationSamples: [(magnification: CGFloat, time: Date)] = []
    // SVG anchor point computed at gesture start, reused throughout
    @State private var zoomAnchorSVG: CGPoint = .zero
    // Whether a zoom or drag gesture is active — disables marker taps
    @State private var isGesturing: Bool = false
    // Briefly highlight tapped marker before navigating
    @State private var tappedMarkerID: UUID?
    
    // The scale at which the Canvas is actually rasterized.
    // Only updated when gestures end so the Canvas doesn't re-render mid-gesture.
    @State private var renderScale: CGFloat = 10.0
    // Whether we have centered on the actual city data (not just fallback)
    @State private var hasCenteredOnCities: Bool = false
    // Briefly highlight a marker after "Reveal on Map"
    @State private var highlightedMarkerID: UUID?
    
    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let baseScale = min(
                viewSize.width / GeoProjection.svgWidth,
                viewSize.height / GeoProjection.svgHeight
            )
            
            mapContent(viewSize: viewSize, baseScale: baseScale)
                .onAppear {
                    if !mapHasInitialized && viewSize.width > 0 && viewSize.height > 0 {
                        centerOnCities(viewSize: viewSize, baseScale: baseScale)
                        mapHasInitialized = !cities.isEmpty
                        hasCenteredOnCities = !cities.isEmpty
                    }
                }
                .onChange(of: viewSize) { _, newSize in
                    if !mapHasInitialized && newSize.width > 0 && newSize.height > 0 {
                        let newBaseScale = min(
                            newSize.width / GeoProjection.svgWidth,
                            newSize.height / GeoProjection.svgHeight
                        )
                        centerOnCities(viewSize: newSize, baseScale: newBaseScale)
                        mapHasInitialized = !cities.isEmpty
                        hasCenteredOnCities = !cities.isEmpty
                    }
                }
                .onChange(of: mapScale) { _, newScale in
                    isZoomedOut = newScale < 15.0
                }
                .onChange(of: cities.count) { _, newCount in
                    if newCount > 0 && !hasCenteredOnCities && viewSize.width > 0 {
                        centerOnCities(viewSize: viewSize, baseScale: baseScale)
                        mapHasInitialized = true
                        hasCenteredOnCities = true
                    }
                }
                .onChange(of: mapHasInitialized) { _, newValue in
                    if !newValue {
                        hasCenteredOnCities = false
                    }
                }
                .onChange(of: recenterOnAllCities) { _, newValue in
                    if newValue {
                        animateToCities(viewSize: viewSize, baseScale: baseScale)
                        recenterOnAllCities = false
                    }
                }
                .onChange(of: centerOnCity?.id) { _, _ in
                    if let city = centerOnCity {
                        animateToCity(city, viewSize: viewSize, baseScale: baseScale)
                        highlightedMarkerID = city.id
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation(.easeOut(duration: 0.5)) {
                                highlightedMarkerID = nil
                            }
                        }
                    }
                }
        }
        .clipped()
        .background(AppTheme.shared.colors.mapOcean)
    }
    
    @ViewBuilder
    private func mapContent(viewSize: CGSize, baseScale: CGFloat) -> some View {
        let svgWidth = GeoProjection.svgWidth
        let svgHeight = GeoProjection.svgHeight
        let minScale = citiesFitScale(viewSize: viewSize, baseScale: baseScale)
        let rubberBandMinScale = minScale * 0.7
        let canvasEffective = baseScale * renderScale
        let canvasWidth = svgWidth * canvasEffective
        let canvasHeight = svgHeight * canvasEffective
        let liveZoom = mapScale / renderScale
        
        Canvas { context, size in
            for country in countries {
                var transform = CGAffineTransform(
                    scaleX: canvasEffective, y: canvasEffective
                )
                if let transformedPath = country.path.copy(using: &transform) {
                    context.fill(
                        Path(transformedPath),
                        with: .color(AppTheme.shared.colors.svgCountryFill)
                    )
                }
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .overlay {
            markersOverlay(canvasEffective: canvasEffective, liveZoom: liveZoom, isGesturing: isGesturing, viewSize: viewSize)
        }
        .scaleEffect(liveZoom, anchor: .topLeading)
        .offset(mapOffset)
        .gesture(dragGesture(viewSize: viewSize, baseScale: baseScale))
        .gesture(magnifyGesture(viewSize: viewSize, baseScale: baseScale, minScale: minScale, rubberBandMinScale: rubberBandMinScale, svgWidth: svgWidth, svgHeight: svgHeight))
    }
    
    /// Returns true if any two on-screen markers overlap — all switch to dots
    private func anyMarkersColliding(canvasEffective: CGFloat, liveZoom: CGFloat, viewSize: CGSize) -> Bool {
        let threshold: CGFloat = 36.0
        let canvasThreshold = threshold / liveZoom
        let canvasThresholdSq = canvasThreshold * canvasThreshold
        let margin: CGFloat = 40.0
        
        struct Pos {
            let x: CGFloat
            let y: CGFloat
        }
        
        var onScreen: [Pos] = []
        for cityWeather in cities {
            let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
            let passesFilter = !filterSunny || (forecast.condition == .clear && (forecast.cloudCover ?? 1.0) < 0.30)
            let hasData = selectedDayOffset == -1
                ? cityWeather.hasCurrentData(forOverlay: overlayMode)
                : forecast.hasData(forOverlay: overlayMode)
            guard passesFilter, hasData else { continue }
            let svgPos = GeoProjection.geoToSVG(
                latitude: cityWeather.city.latitude,
                longitude: cityWeather.city.longitude
            )
            let canvasX = svgPos.x * canvasEffective
            let canvasY = svgPos.y * canvasEffective
            let screenX = canvasX * liveZoom + mapOffset.width
            let screenY = canvasY * liveZoom + mapOffset.height
            guard screenX > -margin && screenX < viewSize.width + margin &&
                  screenY > -margin && screenY < viewSize.height + margin else { continue }
            onScreen.append(Pos(x: canvasX, y: canvasY))
        }
        
        for i in 0..<onScreen.count {
            for j in (i + 1)..<onScreen.count {
                let dx = onScreen[i].x - onScreen[j].x
                let dy = onScreen[i].y - onScreen[j].y
                if dx * dx + dy * dy < canvasThresholdSq {
                    return true
                }
            }
        }
        return false
    }
    
    @ViewBuilder
    private func markersOverlay(canvasEffective: CGFloat, liveZoom: CGFloat, isGesturing: Bool, viewSize: CGSize) -> some View {
        let showDots = anyMarkersColliding(canvasEffective: canvasEffective, liveZoom: liveZoom, viewSize: viewSize)
        
        ForEach(cities) { cityWeather in
            let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
            let passesFilter = !filterSunny || (forecast.condition == .clear && (forecast.cloudCover ?? 1.0) < 0.30)
            let hasData = selectedDayOffset == -1
                ? cityWeather.hasCurrentData(forOverlay: overlayMode)
                : forecast.hasData(forOverlay: overlayMode)
            let svgPos = GeoProjection.geoToSVG(
                latitude: cityWeather.city.latitude,
                longitude: cityWeather.city.longitude
            )
            
            WeatherMarker(
                cityWeather: cityWeather,
                dayOffset: selectedDayOffset,
                isCompact: isZoomedOut,
                namespace: namespace,
                showCloudCover: showCloudCover,
                overlayMode: overlayMode,
                filterSunny: filterSunny,
                passesFilter: passesFilter,
                isPlaying: isPlaying,
                displayMode: showDots ? .dot : .card
            )
            .scaleEffect(((tappedMarkerID == cityWeather.id || highlightedMarkerID == cityWeather.id || (showingCityDetail && tappedCity?.id == cityWeather.id)) ? 1.5 : 1.0) / liveZoom, anchor: .center)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: tappedMarkerID)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: highlightedMarkerID)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: showingCityDetail)
            .position(
                x: svgPos.x * canvasEffective,
                y: svgPos.y * canvasEffective
            )
            .opacity(passesFilter && hasData ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: passesFilter)
            .animation(.easeInOut(duration: 0.3), value: hasData)
            .allowsHitTesting(passesFilter && hasData && !isGesturing)
            .onTapGesture {
                tappedCity = cityWeather
                tappedMarkerID = cityWeather.id
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showingCityDetail = true
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                    tappedMarkerID = nil
                }
            }
        }
    }
    
    /// Clamps the offset so the user can only pan within the region visible at the initial fit-all-cities view.
    /// At minimum zoom (fit scale), panning is completely locked.
    /// When zoomed in, panning is allowed only enough to see the area that was visible at fit scale.
    private func clampOffset(_ offset: CGSize, viewSize: CGSize, baseScale: CGFloat, scale: CGFloat? = nil) -> CGSize {
        let currentScale = scale ?? mapScale
        guard !cities.isEmpty else { return offset }
        
        let center = citiesCenterSVG()
        let fitScale = citiesFitScale(viewSize: viewSize, baseScale: baseScale)
        let effective = baseScale * currentScale
        
        // The offset that perfectly centers all cities
        let idealX = viewSize.width / 2 - center.x * effective
        let idealY = viewSize.height / 2 - center.y * effective
        
        // How much of the SVG (in points) was visible at the fit-all-cities zoom level
        let fitEffective = baseScale * fitScale
        let visibleSVGWidth = viewSize.width / fitEffective
        let visibleSVGHeight = viewSize.height / fitEffective
        
        // How much of the SVG (in points) is visible at the current zoom level
        let currentSVGWidth = viewSize.width / effective
        let currentSVGHeight = viewSize.height / effective
        
        // The max drift in SVG coordinates is the difference between what was visible and what is now visible
        // divided by 2 (since we can drift in either direction from center)
        let maxDriftSVGX = max(0, (visibleSVGWidth - currentSVGWidth) / 2)
        let maxDriftSVGY = max(0, (visibleSVGHeight - currentSVGHeight) / 2)
        
        // Convert SVG drift to screen-space drift
        let maxDriftX = maxDriftSVGX * effective
        let maxDriftY = maxDriftSVGY * effective
        
        return CGSize(
            width: min(max(offset.width, idealX - maxDriftX), idealX + maxDriftX),
            height: min(max(offset.height, idealY - maxDriftY), idealY + maxDriftY)
        )
    }
    
    private func dragGesture(viewSize: CGSize, baseScale: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                isGesturing = true
                let raw = CGSize(
                    width: mapLastOffset.width + value.translation.width,
                    height: mapLastOffset.height + value.translation.height
                )
                mapOffset = clampOffset(raw, viewSize: viewSize, baseScale: baseScale)
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation
                let momentumX = velocity.width - value.translation.width
                let momentumY = velocity.height - value.translation.height
                var target = CGSize(
                    width: mapOffset.width + momentumX,
                    height: mapOffset.height + momentumY
                )
                target = clampOffset(target, viewSize: viewSize, baseScale: baseScale)
                withAnimation(.spring(response: 0.6, dampingFraction: 1.0)) {
                    mapOffset = target
                }
                mapLastOffset = target
                isGesturing = false
            }
    }
    
    private func magnifyGesture(viewSize: CGSize, baseScale: CGFloat, minScale: CGFloat, rubberBandMinScale: CGFloat, svgWidth: CGFloat, svgHeight: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isGesturing = true
                // Cap how fast scale can change per frame (~4x per second max)
                let maxScaleRatePerSec: CGFloat = 4.0
                let rawScale = mapLastScale * value.magnification
                let targetScale = min(max(rawScale, rubberBandMinScale), rubberBandMaxScale)
                let ratio = targetScale / mapScale
                let now = Date.now
                let dt = magnificationSamples.last.map { now.timeIntervalSince($0.time) } ?? (1.0 / 60.0)
                let maxRatio = exp(maxScaleRatePerSec * max(dt, 1.0 / 120.0))
                let clampedRatio = max(min(ratio, maxRatio), 1.0 / maxRatio)
                let newScale = min(max(mapScale * clampedRatio, rubberBandMinScale), rubberBandMaxScale)
                
                let viewCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                
                // Compute and store the SVG anchor on the first frame of the gesture
                if magnificationSamples.isEmpty {
                    let startEffective = baseScale * mapLastScale
                    zoomAnchorSVG = CGPoint(
                        x: (viewCenter.x - mapLastOffset.width) / startEffective,
                        y: (viewCenter.y - mapLastOffset.height) / startEffective
                    )
                }
                
                // Reposition using the stable anchor
                let newEffective = baseScale * newScale
                mapOffset = CGSize(
                    width: viewCenter.x - zoomAnchorSVG.x * newEffective,
                    height: viewCenter.y - zoomAnchorSVG.y * newEffective
                )
                magnificationSamples.append((value.magnification, now))
                magnificationSamples.removeAll { now.timeIntervalSince($0.time) > 0.1 }
                mapScale = newScale
            }
            .onEnded { value in
                magnificationSamples.removeAll()
                
                // Clamp to valid range (snap back from rubber-band)
                let finalScale = min(max(mapScale, minScale), maxScale)
                
                let viewCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                let targetEffective = baseScale * finalScale
                var targetOffset = CGSize(
                    width: viewCenter.x - zoomAnchorSVG.x * targetEffective,
                    height: viewCenter.y - zoomAnchorSVG.y * targetEffective
                )
                
                if finalScale <= minScale {
                    let center = citiesCenterSVG()
                    targetOffset = CGSize(
                        width: viewSize.width / 2 - center.x * targetEffective,
                        height: viewSize.height / 2 - center.y * targetEffective
                    )
                }
                
                // Clamp offset so cities stay on screen
                targetOffset = clampOffset(targetOffset, viewSize: viewSize, baseScale: baseScale, scale: finalScale)
                
                if finalScale != mapScale {
                    // Rubber-band snap back
                    withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                        mapScale = finalScale
                        mapOffset = targetOffset
                    }
                } else {
                    mapOffset = targetOffset
                }
                mapLastScale = finalScale
                mapLastOffset = targetOffset
                renderScale = finalScale
                isGesturing = false
            }
    }
    
    private func centerOnCities(viewSize: CGSize, baseScale: CGFloat) {
        guard !cities.isEmpty else {
            // Fallback: center on world mid-point
            let worldCenter = GeoProjection.geoToSVG(latitude: 35.0, longitude: 105.0)
            let initialScale: CGFloat = 10.0
            mapScale = initialScale
            mapLastScale = initialScale
            renderScale = initialScale
            let effective = baseScale * initialScale
            mapOffset = CGSize(
                width: viewSize.width / 2 - worldCenter.x * effective,
                height: viewSize.height / 2 - worldCenter.y * effective
            )
            mapLastOffset = mapOffset
            isZoomedOut = initialScale < 15.0
            return
        }
        
        // Compute bounding box of all cities in SVG coordinates
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for city in cities {
            let svgPos = GeoProjection.geoToSVG(
                latitude: city.city.latitude,
                longitude: city.city.longitude
            )
            minX = min(minX, svgPos.x)
            maxX = max(maxX, svgPos.x)
            minY = min(minY, svgPos.y)
            maxY = max(maxY, svgPos.y)
        }
        
        let centerSVG = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let svgSpanX = maxX - minX
        let svgSpanY = maxY - minY
        
        // Compute scale to fit all cities with some padding
        let padding: CGFloat = 1.4
        let minScale: CGFloat = viewSize.height / (GeoProjection.svgHeight * baseScale)
        var fitScale: CGFloat
        if svgSpanX < 0.001 && svgSpanY < 0.001 {
            // Single city or all same location
            fitScale = 10.0
        } else {
            let scaleX = viewSize.width / (svgSpanX * baseScale * padding)
            let scaleY = viewSize.height / (svgSpanY * baseScale * padding)
            fitScale = min(scaleX, scaleY)
            fitScale = min(max(fitScale, minScale), maxScale)
        }
        
        mapScale = fitScale
        mapLastScale = fitScale
        renderScale = fitScale
        let effective = baseScale * fitScale
        mapOffset = CGSize(
            width: viewSize.width / 2 - centerSVG.x * effective,
            height: viewSize.height / 2 - centerSVG.y * effective
        )
        mapLastOffset = mapOffset
        isZoomedOut = fitScale < 15.0
    }
    
    private func animateToCities(viewSize: CGSize, baseScale: CGFloat) {
        guard !cities.isEmpty else { return }
        
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        
        for city in cities {
            let svgPos = GeoProjection.geoToSVG(
                latitude: city.city.latitude,
                longitude: city.city.longitude
            )
            minX = min(minX, svgPos.x)
            maxX = max(maxX, svgPos.x)
            minY = min(minY, svgPos.y)
            maxY = max(maxY, svgPos.y)
        }
        
        let centerSVG = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let svgSpanX = maxX - minX
        let svgSpanY = maxY - minY
        
        let padding: CGFloat = 1.4
        let minScale: CGFloat = viewSize.height / (GeoProjection.svgHeight * baseScale)
        var fitScale: CGFloat
        if svgSpanX < 0.001 && svgSpanY < 0.001 {
            fitScale = 10.0
        } else {
            let scaleX = viewSize.width / (svgSpanX * baseScale * padding)
            let scaleY = viewSize.height / (svgSpanY * baseScale * padding)
            fitScale = min(scaleX, scaleY)
            fitScale = min(max(fitScale, minScale), maxScale)
        }
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            mapScale = fitScale
            mapLastScale = fitScale
            let effective = baseScale * fitScale
            mapOffset = CGSize(
                width: viewSize.width / 2 - centerSVG.x * effective,
                height: viewSize.height / 2 - centerSVG.y * effective
            )
            mapLastOffset = mapOffset
        }
        renderScale = fitScale
    }
    
    private func animateToCity(_ cityWeather: CityWeather, viewSize: CGSize, baseScale: CGFloat) {
        let svgPoint = GeoProjection.geoToSVG(
            latitude: cityWeather.city.latitude,
            longitude: cityWeather.city.longitude
        )
        let fitScale = citiesFitScale(viewSize: viewSize, baseScale: baseScale)
        let targetScale: CGFloat = min(fitScale * 3.0, maxScale)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            mapScale = targetScale
            mapLastScale = targetScale
            let effective = baseScale * targetScale
            mapOffset = CGSize(
                width: viewSize.width / 2 - svgPoint.x * effective,
                height: viewSize.height / 2 - svgPoint.y * effective
            )
            mapLastOffset = mapOffset
        }
        renderScale = targetScale
    }
}


