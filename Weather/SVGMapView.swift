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
    
    private let maxScale: CGFloat = 30.0
    private let rubberBandMaxScale: CGFloat = 40.0
    
    // Magnification samples used for per-frame rate limiting
    @State private var magnificationSamples: [(magnification: CGFloat, time: Date)] = []
    // SVG anchor point computed at gesture start, reused throughout
    @State private var zoomAnchorSVG: CGPoint = .zero
    // Whether a zoom or drag gesture is active — disables marker taps
    @State private var isGesturing: Bool = false
    
    // The scale at which the Canvas is actually rasterized.
    // Only updated when gestures end so the Canvas doesn't re-render mid-gesture.
    @State private var renderScale: CGFloat = 10.0
    
    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let baseScale = min(
                viewSize.width / GeoProjection.svgWidth,
                viewSize.height / GeoProjection.svgHeight
            )
            
            mapContent(viewSize: viewSize, baseScale: baseScale)
                .onChange(of: viewSize) { _, newSize in
                    if !mapHasInitialized && newSize.width > 0 && newSize.height > 0 {
                        let newBaseScale = min(
                            newSize.width / GeoProjection.svgWidth,
                            newSize.height / GeoProjection.svgHeight
                        )
                        centerOnEurope(viewSize: newSize, baseScale: newBaseScale)
                        mapHasInitialized = true
                    }
                }
                .onChange(of: mapScale) { _, newScale in
                    isZoomedOut = newScale < 15.0
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
            markersOverlay(canvasEffective: canvasEffective, liveZoom: liveZoom, isGesturing: isGesturing)
        }
        .scaleEffect(liveZoom, anchor: .topLeading)
        .offset(mapOffset)
        .gesture(dragGesture())
        .gesture(magnifyGesture(viewSize: viewSize, baseScale: baseScale, minScale: minScale, rubberBandMinScale: rubberBandMinScale, svgWidth: svgWidth, svgHeight: svgHeight))
    }
    
    @ViewBuilder
    private func markersOverlay(canvasEffective: CGFloat, liveZoom: CGFloat, isGesturing: Bool) -> some View {
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
                isPlaying: isPlaying
            )
            .scaleEffect(1.0 / liveZoom, anchor: .center)
            .position(
                x: svgPos.x * canvasEffective,
                y: svgPos.y * canvasEffective
            )
            .opacity(passesFilter ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: passesFilter)
            .allowsHitTesting(passesFilter && !isGesturing)
            .onTapGesture {
                tappedCity = cityWeather
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingCityDetail = true
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
    
    private func centerOnEurope(viewSize: CGSize, baseScale: CGFloat) {
        let europeCenter = GeoProjection.geoToSVG(latitude: 50.0, longitude: 10.0)
        let initialScale: CGFloat = 10.0
        mapScale = initialScale
        mapLastScale = initialScale
        renderScale = initialScale
        let effective = baseScale * initialScale
        mapOffset = CGSize(
            width: viewSize.width / 2 - europeCenter.x * effective,
            height: viewSize.height / 2 - europeCenter.y * effective
        )
        mapLastOffset = mapOffset
        isZoomedOut = initialScale < 15.0
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
