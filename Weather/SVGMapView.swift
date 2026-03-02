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
    
    @State private var lastMagnification: CGFloat = 1.0
    @State private var lastMagnificationTime: Date = .now
    
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
            let svgWidth = GeoProjection.svgWidth
            let svgHeight = GeoProjection.svgHeight
            
            // Minimum scale: SVG map height must fill the view height
            let minScale = viewSize.height / (svgHeight * baseScale)
            let rubberBandMinScale = minScale * 0.7
            
            // Canvas is rendered at renderScale (fixed between gestures)
            let canvasEffective = baseScale * renderScale
            let canvasWidth = svgWidth * canvasEffective
            let canvasHeight = svgHeight * canvasEffective
            
            // Live zoom ratio applied as a GPU transform on top
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
                // Markers positioned in canvas coordinates
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
                    // Counter-scale the liveZoom so icons stay constant screen size
                    .scaleEffect(1.0 / liveZoom, anchor: .center)
                    .position(
                        x: svgPos.x * canvasEffective,
                        y: svgPos.y * canvasEffective
                    )
                    .opacity(passesFilter ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: passesFilter)
                    .allowsHitTesting(passesFilter)
                    .onTapGesture {
                        tappedCity = cityWeather
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            showingCityDetail = true
                        }
                    }
                }
            }
            // Scale the whole canvas+markers as one GPU layer for smooth zoom
            .scaleEffect(liveZoom, anchor: .topLeading)
            .offset(mapOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
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
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        // Allow rubber-band past minScale during gesture
                        let newScale = min(max(mapLastScale * value.magnification, rubberBandMinScale), maxScale)
                        let viewCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                        let startEffective = baseScale * mapLastScale
                        let svgX = (viewCenter.x - mapLastOffset.width) / startEffective
                        let svgY = (viewCenter.y - mapLastOffset.height) / startEffective
                        let newEffective = baseScale * newScale
                        mapOffset = CGSize(
                            width: viewCenter.x - svgX * newEffective,
                            height: viewCenter.y - svgY * newEffective
                        )
                        let now = Date.now
                        lastMagnification = value.magnification
                        lastMagnificationTime = now
                        mapScale = newScale
                    }
                    .onEnded { value in
                        let dt = Date.now.timeIntervalSince(lastMagnificationTime)
                        let magnificationRatio = value.magnification / max(lastMagnification, 0.01)
                        let velocity = dt > 0.001 ? magnificationRatio : 1.0
                        let momentumFactor = pow(velocity, min(CGFloat(0.15 / max(dt, 0.001)), 3.0))
                        // Clamp to minScale (not rubberBandMinScale) — snaps back
                        let projectedScale = min(max(mapScale * momentumFactor, minScale), maxScale)
                        
                        let viewCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
                        let currentEffective = baseScale * mapScale
                        let svgX = (viewCenter.x - mapOffset.width) / currentEffective
                        let svgY = (viewCenter.y - mapOffset.height) / currentEffective
                        let targetEffective = baseScale * projectedScale
                        var targetOffset = CGSize(
                            width: viewCenter.x - svgX * targetEffective,
                            height: viewCenter.y - svgY * targetEffective
                        )
                        
                        // At minimum zoom, center the map in the view
                        if projectedScale == minScale {
                            let contentW = svgWidth * baseScale * minScale
                            let contentH = svgHeight * baseScale * minScale
                            targetOffset = CGSize(
                                width: (viewSize.width - contentW) / 2,
                                height: (viewSize.height - contentH) / 2
                            )
                        }
                        
                        withAnimation(.spring(response: 0.4, dampingFraction: 1.0)) {
                            mapScale = projectedScale
                            mapOffset = targetOffset
                        }
                        mapLastScale = projectedScale
                        mapLastOffset = targetOffset
                        // Re-rasterize the canvas at the new zoom level
                        renderScale = projectedScale
                    }
            )
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
