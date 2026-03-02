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
                .onChange(of: recenterOnAllCities) { _, newValue in
                    if newValue {
                        animateToCities(viewSize: viewSize, baseScale: baseScale)
                        recenterOnAllCities = false
                    }
                }
                .onChange(of: centerOnCity?.id) { _, _ in
                    if let city = centerOnCity {
                        animateToCity(city, viewSize: viewSize, baseScale: baseScale)
                    }
                }
        }
        .clipped()
        .background(Color.black)
    }
    
    @ViewBuilder
    private func mapContent(viewSize: CGSize, baseScale: CGFloat) -> some View {
        let svgWidth = GeoProjection.svgWidth
        let svgHeight = GeoProjection.svgHeight
        let minScale = viewSize.height / (svgHeight * baseScale)
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
                        with: .color(.gray.opacity(0.2))
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
        .gesture(dragGesture())
        .gesture(magnifyGesture(viewSize: viewSize, baseScale: baseScale, minScale: minScale, rubberBandMinScale: rubberBandMinScale, svgWidth: svgWidth, svgHeight: svgHeight))
    }
    
    /// Returns true if any two on-screen markers overlap — all switch to dots
    private func anyMarkersColliding(canvasEffective: CGFloat, liveZoom: CGFloat, viewSize: CGSize) -> Bool {
        let threshold: CGFloat = 36.0
        let canvasThreshold = threshold / liveZoom
        let canvasThresholdSq = canvasThreshold * canvasThreshold
        
        // Margin so markers near the edge are included
        let margin: CGFloat = 40.0
        
        struct Pos {
            let x: CGFloat
            let y: CGFloat
        }
        
        var onScreen: [Pos] = []
        for cityWeather in cities {
            let forecast = cityWeather.forecast(for: selectedDayOffset)
            let passesFilter = !filterSunny || (forecast.condition == .clear && forecast.cloudCover < 0.30)
            guard passesFilter else { continue }
            let svgPos = GeoProjection.geoToSVG(
                latitude: cityWeather.city.latitude,
                longitude: cityWeather.city.longitude
            )
            let canvasX = svgPos.x * canvasEffective
            let canvasY = svgPos.y * canvasEffective
            
            // Convert to screen coordinates
            let screenX = canvasX * liveZoom + mapOffset.width
            let screenY = canvasY * liveZoom + mapOffset.height
            
            // Only include markers visible on screen
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
            let forecast = cityWeather.forecast(for: selectedDayOffset)
            let passesFilter = !filterSunny || (forecast.condition == .clear && forecast.cloudCover < 0.30)
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
                filterSunny: filterSunny,
                passesFilter: passesFilter,
                isPlaying: isPlaying,
                showAsDot: showDots
            )
            .scaleEffect((tappedMarkerID == cityWeather.id ? 1.5 : 1.0) / liveZoom, anchor: .center)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: tappedMarkerID)
            .position(
                x: svgPos.x * canvasEffective,
                y: svgPos.y * canvasEffective
            )
            .opacity(passesFilter ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: passesFilter)
            .allowsHitTesting(passesFilter && !isGesturing)
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
    
    private func dragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                isGesturing = true
                mapOffset = CGSize(
                    width: mapLastOffset.width + value.translation.width,
                    height: mapLastOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation
                let momentumX = velocity.width - value.translation.width
                let momentumY = velocity.height - value.translation.height
                let target = CGSize(
                    width: mapOffset.width + momentumX,
                    height: mapOffset.height + momentumY
                )
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
                    let contentW = svgWidth * baseScale * minScale
                    let contentH = svgHeight * baseScale * minScale
                    targetOffset = CGSize(
                        width: (viewSize.width - contentW) / 2,
                        height: (viewSize.height - contentH) / 2
                    )
                }
                
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
        let targetScale: CGFloat = 4.0
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
