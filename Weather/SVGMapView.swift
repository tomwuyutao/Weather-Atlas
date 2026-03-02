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
    
    var centerOnCity: CityWeather?
    
    @State private var scale: CGFloat = 10.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 10.0
    @State private var lastOffset: CGSize = .zero
    @State private var hasInitialized: Bool = false
    @State private var pinchAnchor: CGPoint = .zero
    
    private let minScale: CGFloat = 0.8
    private let maxScale: CGFloat = 30.0
    
    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let baseScale = min(
                viewSize.width / GeoProjection.svgWidth,
                viewSize.height / GeoProjection.svgHeight
            )
            let effectiveScale = baseScale * scale
            
            ZStack {
                // Country shapes — drawn at origin, offset applied to container
                Canvas { context, size in
                    for country in countries {
                        var transform = CGAffineTransform(
                            scaleX: effectiveScale, y: effectiveScale
                        )
                        if let transformedPath = country.path.copy(using: &transform) {
                            context.fill(
                                Path(transformedPath),
                                with: .color(.gray.opacity(0.2))
                            )
                        }
                    }
                }
                .frame(
                    width: GeoProjection.svgWidth * effectiveScale,
                    height: GeoProjection.svgHeight * effectiveScale
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                
                // Weather markers
                ForEach(cities) { cityWeather in
                    let forecast = cityWeather.forecast(for: selectedDayOffset)
                    let passesFilter = !filterSunny || (forecast.condition == .clear && forecast.cloudCover < 0.30)
                    let screenPos = GeoProjection.geoToScreen(
                        latitude: cityWeather.city.latitude,
                        longitude: cityWeather.city.longitude,
                        scale: effectiveScale,
                        offset: .zero
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
                    .position(x: screenPos.x, y: screenPos.y)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .offset(offset)
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { value in
                            let velocity = value.predictedEndTranslation
                            let momentumX = velocity.width - value.translation.width
                            let momentumY = velocity.height - value.translation.height
                            let target = CGSize(
                                width: offset.width + momentumX,
                                height: offset.height + momentumY
                            )
                            withAnimation(.spring(response: 0.6, dampingFraction: 1.0)) {
                                offset = target
                            }
                            lastOffset = target
                        },
                    MagnifyGesture()
                        .onChanged { value in
                            let newScale = min(max(lastScale * value.magnification, minScale), maxScale)
                            let anchor = value.startAnchor
                            let anchorPt = CGPoint(
                                x: anchor.x * viewSize.width,
                                y: anchor.y * viewSize.height
                            )
                            // SVG point under the anchor at gesture start
                            let startEffective = baseScale * lastScale
                            let svgX = (anchorPt.x - lastOffset.width) / startEffective
                            let svgY = (anchorPt.y - lastOffset.height) / startEffective
                            // New offset keeps that SVG point under the same screen anchor
                            let newEffective = baseScale * newScale
                            offset = CGSize(
                                width: anchorPt.x - svgX * newEffective,
                                height: anchorPt.y - svgY * newEffective
                            )
                            scale = newScale
                        }
                        .onEnded { _ in
                            lastScale = scale
                            lastOffset = offset
                        }
                )
            )
            .onChange(of: viewSize) { _, newSize in
                if !hasInitialized && newSize.width > 0 && newSize.height > 0 {
                    let newBaseScale = min(
                        newSize.width / GeoProjection.svgWidth,
                        newSize.height / GeoProjection.svgHeight
                    )
                    centerOnEurope(viewSize: newSize, baseScale: newBaseScale)
                    hasInitialized = true
                }
            }
            .onChange(of: scale) { _, newScale in
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
        scale = initialScale
        lastScale = initialScale
        let effective = baseScale * initialScale
        offset = CGSize(
            width: viewSize.width / 2 - europeCenter.x * effective,
            height: viewSize.height / 2 - europeCenter.y * effective
        )
        lastOffset = offset
        isZoomedOut = initialScale < 15.0
    }
    
    private func animateToCity(_ cityWeather: CityWeather, viewSize: CGSize, baseScale: CGFloat) {
        let svgPoint = GeoProjection.geoToSVG(
            latitude: cityWeather.city.latitude,
            longitude: cityWeather.city.longitude
        )
        let targetScale: CGFloat = 4.0
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            scale = targetScale
            lastScale = targetScale
            let effective = baseScale * targetScale
            offset = CGSize(
                width: viewSize.width / 2 - svgPoint.x * effective,
                height: viewSize.height / 2 - svgPoint.y * effective
            )
            lastOffset = offset
        }
    }
}
