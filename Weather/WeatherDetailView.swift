//
//  WeatherDetailView.swift
//  Weather
//
//  Created by Tom on 25/02/2026.
//

import SwiftUI
import WeatherKit

struct WeatherDetailView: View {
    let cityWeather: CityWeather
    @Binding var selectedDayOffset: Int
    let namespace: Namespace.ID
    let onDismiss: () -> Void
    let onAddCity: (() -> Void)?
    let onDeleteCity: (() -> Void)?
    let onRevealOnMap: (() -> Void)?
    let isInSidebar: Bool
    let showCloudCover: Bool
    var previewCurrentHour: Int? = nil
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @State private var internalSelectedDay: Int
    @State private var previousDay: Int
    @State private var chartDragOffset: CGFloat = 0
    @State private var swipeDirection: SwipeDirection = .forward
    
    private enum SwipeDirection {
        case forward, backward
    }
    @State private var showingCloudCover: Bool = false
    @State private var showingDetailMenu: Bool = false
    @State private var dayScrollHasMore: Bool = true
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    
    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }
    
    // Initialize with the day from the map slider
    init(cityWeather: CityWeather, selectedDayOffset: Binding<Int>, namespace: Namespace.ID, onDismiss: @escaping () -> Void, onAddCity: (() -> Void)? = nil, onDeleteCity: (() -> Void)? = nil, onRevealOnMap: (() -> Void)? = nil, isInSidebar: Bool = true, showCloudCover: Bool = false, previewCurrentHour: Int? = nil) {
        self.cityWeather = cityWeather
        self._selectedDayOffset = selectedDayOffset
        self.namespace = namespace
        self.onDismiss = onDismiss
        self.onAddCity = onAddCity
        self.onDeleteCity = onDeleteCity
        self.onRevealOnMap = onRevealOnMap
        self.isInSidebar = isInSidebar
        self.showCloudCover = showCloudCover
        self.previewCurrentHour = previewCurrentHour
        self._internalSelectedDay = State(initialValue: selectedDayOffset.wrappedValue)
        self._previousDay = State(initialValue: selectedDayOffset.wrappedValue)
    }
    
    private var forecast: DailyForecast {
        cityWeather.forecast(for: internalSelectedDay)
    }
    
    /// Use plain cloud icon when animation shows precipitation
    private var detailDisplayIcon: String {
        if forecast.condition == .rain || forecast.condition == .drizzle || forecast.condition == .snow {
            return "cloud.fill"
        }
        return forecast.weatherIcon
    }
    
    private var goingForward: Bool {
        internalSelectedDay >= previousDay
    }
    
    private var effectiveShowCloudCover: Bool {
        false
    }
    
    private var headerBackgroundColor: Color {
        let theme = AppTheme.shared.colors
        switch forecast.condition {
        case .rain: return theme.dotRain
        case .drizzle: return theme.dotDrizzle
        case .snow, .cloudy: return Color(red: 0xB8 / 255, green: 0xCC / 255, blue: 0xD8 / 255)
        default:
            // If the icon is a plain cloud (no sun), use the cloud color regardless of condition
            if detailDisplayIcon == "cloud.fill" {
                return Color(red: 0xB8 / 255, green: 0xCC / 255, blue: 0xD8 / 255)
            }
            return forecast.condition.dotColor
        }
    }

    private var isPopup: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack {
            // Weather condition color block — top half background
            if !isPopup {
                GeometryReader { geo in
                    headerBackgroundColor
                        .frame(height: 350 + geo.safeAreaInsets.top)
                        .frame(maxWidth: .infinity)
                        .ignoresSafeArea(edges: .top)
                }
            }

            // Main content card
            VStack(spacing: isPopup ? 24 : 16) {
                // Header
                if !isPopup {
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            // Large decorative icon — right, slightly cropped
                            Image(systemName: detailDisplayIcon)
                                .font(.system(size: 180))
                                .foregroundStyle(.white)
                                .contentTransition(.symbolEffect(.replace))
                                .opacity(0.35)
                                .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                                .background(alignment: .top) {
                                    WeatherEffectOverlay(
                                        condition: forecast.condition,
                                        isCompact: false,
                                        iconHeight: 220,
                                        iconName: detailDisplayIcon,
                                        dropColor: forecast.condition == .drizzle ? AppTheme.shared.colors.dotRain : nil
                                    )
                                    .id("detail-header-effect-\(internalSelectedDay)-\(forecast.condition.displayName)")
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                                .padding(.trailing, -40)
                                .offset(y: -36)

                            // Temperature + condition — top left, below back button
                            VStack(alignment: .leading, spacing: 6) {
                                Text(tempUnit.display(forecast.daytimeHigh))
                                    .font(.avenir(.largeTitle, weight: .bold))
                                    .dynamicTypeSize(...DynamicTypeSize.large)
                                    .contentTransition(.numericText())
                                    .animation(.smooth(duration: 0.3), value: internalSelectedDay)

                                Text(forecast.condition.localizedDisplayName(locale: locale))
                                    .font(.avenir(.title3, weight: .medium))
                                    .dynamicTypeSize(...DynamicTypeSize.large)
                                    .contentTransition(.opacity)
                                    .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                            }
                            .foregroundStyle(.white)
                            .padding(.leading, 28)
                            .padding(.top, geo.safeAreaInsets.top + 76)
                        }
                    }
                    // fill half the screen height (matches the color block)
                    .frame(height: 350)
                } else {
                    VStack(alignment: .center, spacing: 0) {
                        Text(cityWeather.city.localizedName(locale: locale))
                            .font(.avenir(.title3, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        Text(forecastDateText)
                            .padding(.top, dynamicTypeSize > .large ? 24 : 16)
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.secondary)
                            .dynamicTypeSize(...DynamicTypeSize.large)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.3), value: internalSelectedDay)

                        Image(systemName: detailDisplayIcon)
                            .font(.system(size: 48))
                            .weatherIconStyle(for: detailDisplayIcon)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(height: 56)
                            .background(alignment: .top) {
                                WeatherEffectOverlay(condition: forecast.condition, isCompact: false, iconHeight: 56)
                                    .id("detail-effect-\(internalSelectedDay)-\(forecast.condition.displayName)")
                            }
                            .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                            .padding(.top, 28)

                        Text(tempUnit.display(forecast.daytimeHigh))
                            .font(.avenir(.largeTitle, weight: .bold))
                            .dynamicTypeSize(...DynamicTypeSize.large)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                            .padding(.top, 14)
                            .padding(.trailing, 4)
                            .offset(x: 5)
                    }
                    .dynamicTypeSize(...DynamicTypeSize.large)
                }

                // 10-day forecast horizontal scroll
                if !isPopup {
                    let lastIndex = cityWeather.dailyForecasts.count - 1
                    ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(cityWeather.dailyForecasts.enumerated()), id: \.element.id) { index, dailyForecast in
                                let r: CGFloat = 8
                                let cr = RectangleCornerRadii(
                                    topLeading: index == 0 ? r : 0,
                                    bottomLeading: index == 0 ? r : 0,
                                    bottomTrailing: index == lastIndex ? r : 0,
                                    topTrailing: index == lastIndex ? r : 0
                                )
                                DayForecastBox(
                                    dailyForecast: dailyForecast,
                                    isSelected: internalSelectedDay == dailyForecast.dayOffset,
                                    cornerRadius: cr,
                                    showCloudCover: effectiveShowCloudCover,
                                    cityTimeZone: cityWeather.timeZone
                                )
                                .id(dailyForecast.dayOffset)
                                .onTapGesture {
                                    swipeDirection = dailyForecast.dayOffset >= internalSelectedDay ? .forward : .backward
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        internalSelectedDay = dailyForecast.dayOffset
                                    }
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onScrollGeometryChange(for: Bool.self) { geo in
                        geo.contentOffset.x + geo.containerSize.width < geo.contentSize.width - 1
                    } action: { _, hasMore in
                        dayScrollHasMore = hasMore
                    }
                    .overlay(alignment: .trailing) {
                        if dayScrollHasMore {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .padding(.trailing, 6)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: dayScrollHasMore)
                    .onChange(of: internalSelectedDay) { _, newDay in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            scrollProxy.scrollTo(newDay, anchor: .center)
                        }
                    }
                    }
                    .padding(.horizontal, 8)
                }

                // Chart container — box stays fixed, content slides inside
                ZStack {
                    let insertEdge: Edge = swipeDirection == .forward ? .trailing : .leading
                    let removeEdge: Edge = swipeDirection == .forward ? .leading : .trailing
                    
                    HourlyTimelineChart(
                        hourlyForecasts: forecast.hourlyForecasts,
                        showCloudCover: effectiveShowCloudCover,
                        dayOffset: internalSelectedDay,
                        cityTimeZone: cityWeather.timeZone,
                        previewCurrentHour: previewCurrentHour,
                        lineColor: headerBackgroundColor
                    )
                    .id("hourly-\(internalSelectedDay)")
                    .transition(.asymmetric(
                        insertion: .move(edge: insertEdge).combined(with: .opacity),
                        removal: .move(edge: removeEdge).combined(with: .opacity)
                    ))
                }
                .clipped()
                .offset(x: chartDragOffset)
                .opacity(Double(1.0 - min(abs(chartDragOffset) / 200.0, 0.4)))
                .padding(.top, 12)
                .background(AppTheme.shared.colors.listCardFill, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onChanged { value in
                            let horizontal = value.translation.width
                            let vertical = value.translation.height
                            guard abs(horizontal) > abs(vertical) else { return }
                            // Resist dragging if at boundary
                            let atStart = internalSelectedDay <= 0 && horizontal > 0
                            let atEnd = internalSelectedDay >= 9 && horizontal < 0
                            if atStart || atEnd {
                                chartDragOffset = horizontal * 0.2
                            } else {
                                chartDragOffset = horizontal * 0.6
                            }
                        }
                        .onEnded { value in
                            let horizontal = value.translation.width
                            let vertical = value.translation.height
                            let threshold: CGFloat = 40
                            if abs(horizontal) > abs(vertical) && abs(horizontal) > threshold {
                                // Set direction BEFORE changing internalSelectedDay
                                if horizontal < 0 {
                                    swipeDirection = .forward
                                } else {
                                    swipeDirection = .backward
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if horizontal < 0 && internalSelectedDay < 9 {
                                        internalSelectedDay += 1
                                    } else if horizontal > 0 && internalSelectedDay > 0 {
                                        internalSelectedDay -= 1
                                    }
                                    chartDragOffset = 0
                                }
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    chartDragOffset = 0
                                }
                            }
                        }
                )
                

            }
            .padding(.horizontal, isPopup ? 20 : 16)
            .padding(.top, isPopup ? 36 : 0)
            .padding(.bottom, isPopup ? 24 : 8)
            .frame(maxWidth: isPopup ? 340 : .infinity)
            .onChange(of: internalSelectedDay) { oldValue, newValue in
                previousDay = oldValue
                selectedDayOffset = newValue
            }
            .background {
                if isPopup {
                    RoundedRectangle(cornerRadius: 26)
                        .fill(.thickMaterial)
                }
            }
            .clipShape(isPopup ? AnyShape(RoundedRectangle(cornerRadius: 26)) : AnyShape(Rectangle()))
            .shadow(color: isPopup ? .black.opacity(0.3) : .clear, radius: isPopup ? 20 : 0)
            .overlay(alignment: .topLeading) {
                if isPopup, !isInSidebar, let addAction = onAddCity {
                    Button {
                        addAction()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .themedAccentGlass(tint: AppTheme.shared.colors.accent, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isPopup {
                    HStack(spacing: 8) {
                        if isInSidebar, onDeleteCity != nil || onRevealOnMap != nil {
                            Button {
                                showingDetailMenu = true
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                            .popover(isPresented: $showingDetailMenu) {
                                VStack(alignment: .leading, spacing: 0) {
                                    if let revealAction = onRevealOnMap {
                                        Button {
                                            showingDetailMenu = false
                                            revealAction()
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: "map")
                                                    .font(.system(size: 15))
                                                    .frame(width: 24)
                                                    .foregroundStyle(.primary)
                                                Text("Reveal on Map")
                                                    .font(.avenir(.body, weight: .medium))
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 11)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    if let deleteAction = onDeleteCity {
                                        Button {
                                            showingDetailMenu = false
                                            deleteAction()
                                        } label: {
                                            HStack(spacing: 12) {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 15))
                                                    .frame(width: 24)
                                                    .foregroundStyle(AppTheme.shared.colors.destructive)
                                                Text("Delete City")
                                                    .font(.avenir(.body, weight: .medium))
                                                    .foregroundStyle(AppTheme.shared.colors.destructive)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 11)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 8)
                                .frame(width: 220)
                                .themedPopoverBackground()
                                .presentationCompactAdaptation(.popover)
                            }
                        }

                        // X button in upper right corner (popup only)
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .themedGlass(in: .circle)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                }
            }

        }
        .frame(maxHeight: isPopup ? nil : .infinity, alignment: .top)

        .contentShape(Rectangle())
        .gesture(
            isPopup ? nil : DragGesture(minimumDistance: 50, coordinateSpace: .global)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    // Only trigger on right swipe (and mostly horizontal)
                    if horizontal > 80 && abs(horizontal) > abs(vertical) * 1.5 {
                        onDismiss()
                    }
                }
        )
        .matchedGeometryEffect(id: isPopup ? (isInSidebar ? "sidebar-\(cityWeather.id)" : "marker-\(cityWeather.id)") : "", in: namespace, isSource: isPopup)
        .transition(isPopup ? .scale(scale: 0.5).combined(with: .opacity) : .identity)
    }
    
    private var forecastDateText: String {
        // Use the city's timezone so day labels match the city's local date
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = cityWeather.timeZone
        let cityToday = cityCalendar.startOfDay(for: Date())
        
        if let date = cityCalendar.date(byAdding: .day, value: internalSelectedDay, to: cityToday) {
            if internalSelectedDay == 0 {
                return localizedString("Today", locale: locale)
            } else if internalSelectedDay == 1 {
                return localizedString("Tomorrow", locale: locale)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEEMMMMd", options: 0, locale: locale)
                formatter.locale = locale
                formatter.timeZone = cityWeather.timeZone
                return formatter.string(from: date)
            }
        }
        return ""
    }
}

// MARK: - Animatable helpers for chart line

struct AnimatablePointList: VectorArithmetic {
    var values: [Double]
    
    static var zero: AnimatablePointList { .init(values: []) }
    
    static func + (lhs: AnimatablePointList, rhs: AnimatablePointList) -> AnimatablePointList {
        let count = max(lhs.values.count, rhs.values.count)
        var result = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let l = i < lhs.values.count ? lhs.values[i] : 0
            let r = i < rhs.values.count ? rhs.values[i] : 0
            result[i] = l + r
        }
        return .init(values: result)
    }
    
    static func - (lhs: AnimatablePointList, rhs: AnimatablePointList) -> AnimatablePointList {
        let count = max(lhs.values.count, rhs.values.count)
        var result = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let l = i < lhs.values.count ? lhs.values[i] : 0
            let r = i < rhs.values.count ? rhs.values[i] : 0
            result[i] = l - r
        }
        return .init(values: result)
    }
    
    mutating func scale(by rhs: Double) {
        for i in values.indices { values[i] *= rhs }
    }
    
    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}

// MARK: - Chart line shape

struct HourlyChartLineShape: Shape {
    var pointYValues: AnimatablePointList
    let pointXPositions: [CGFloat]
    let gapRadius: CGFloat
    
    var animatableData: AnimatablePointList {
        get { pointYValues }
        set { pointYValues = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = zip(pointXPositions, pointYValues.values).map { CGPoint(x: $0, y: $1) }
        guard points.count >= 2 else { return path }
        
        // Sample the full Catmull-Rom spline with high resolution for smooth curves
        let segSteps = 40  // samples per segment
        var allPoints: [CGPoint] = []
        
        for i in 0..<(points.count - 1) {
            // Mirror endpoints for smoother curve at the edges
            let p0 = i > 0 ? points[i - 1] : CGPoint(x: 2 * points[i].x - points[i + 1].x, y: 2 * points[i].y - points[i + 1].y)
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = i + 2 < points.count ? points[i + 2] : CGPoint(x: 2 * p2.x - p1.x, y: 2 * p2.y - p1.y)
            
            for s in 0...segSteps {
                let t = CGFloat(s) / CGFloat(segSteps)
                let x = catmullRom(t: t, p0: p0.x, p1: p1.x, p2: p2.x, p3: p3.x)
                let y = catmullRom(t: t, p0: p0.y, p1: p1.y, p2: p2.y, p3: p3.y)
                allPoints.append(CGPoint(x: x, y: y))
            }
        }
        
        // Draw the sampled curve, skipping points near data points
        var drawing = false
        for pt in allPoints {
            let nearDataPoint = points.contains { dp in
                abs(pt.x - dp.x) < gapRadius
            }
            if nearDataPoint {
                drawing = false
            } else {
                if !drawing {
                    path.move(to: pt)
                    drawing = true
                } else {
                    path.addLine(to: pt)
                }
            }
        }
        
        return path
    }
    
    private func catmullRom(t: CGFloat, p0: CGFloat, p1: CGFloat, p2: CGFloat, p3: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            (2 * p1) +
            (-p0 + p2) * t +
            (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
            (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }
}

// MARK: - Chart timeline view

struct HourlyTimelineChart: View {
    let hourlyForecasts: [HourlyForecast]
    let showCloudCover: Bool
    var dayOffset: Int = 0
    var cityTimeZone: TimeZone = .current
    var previewCurrentHour: Int? = nil
    var lineColor: Color = AppTheme.shared.colors.destructive
    
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    
    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }
    
    private var currentCityHour: Int? {
        guard dayOffset == 0 else { return nil }
        if let override = previewCurrentHour { return override }
        var calendar = Calendar.current
        calendar.timeZone = cityTimeZone
        return calendar.component(.hour, from: Date())
    }
    
    private func isPastHour(_ hour: Int) -> Bool {
        guard let currentHour = currentCityHour else { return false }
        return hour < currentHour
    }
    
    #if os(macOS)
    private let totalHeight: CGFloat = 156
    #else
    private let totalHeight: CGFloat = 220
    #endif
    private let hourLabelHeight: CGFloat = 18  // fixed hour label at top
    private let topPadding: CGFloat = 6        // space below hour label
    private let iconHeight: CGFloat = 24
    private let iconToValue: CGFloat = 8       // gap between icon bottom and value center
    private let valueHeight: CGFloat = 18      // height of value text (sits on line)
    
    // Chart zone: area where the line center can move
    private var chartTop: CGFloat { hourLabelHeight + topPadding + iconHeight + iconToValue + valueHeight / 2 }
    private var chartBottom: CGFloat { totalHeight - valueHeight / 2 - 4 }
    private var chartZone: CGFloat { chartBottom - chartTop }
    
    private var dataPoints: [HourlyForecast] {
        hourlyForecasts.filter { [7, 9, 11, 13, 15, 17, 19].contains($0.hour) }
    }
    
    private func value(for forecast: HourlyForecast) -> Double {
        showCloudCover ? Double(forecast.cloudCoverPercent) : forecast.temperature
    }
    
    private var valueRange: (min: Double, max: Double) {
        if showCloudCover {
            return (0, 100)
        } else {
            let temps = dataPoints.map(\.temperature)
            let minT = temps.min() ?? 10
            let maxT = temps.max() ?? 20
            let padding = max((maxT - minT) * 0.25, 2.0)
            return (minT - padding, maxT + padding)
        }
    }
    
    // Returns the Y coordinate of the line point (higher value = lower Y = higher on screen)
    private func lineY(for val: Double) -> CGFloat {
        let range = valueRange.max - valueRange.min
        guard range > 0 else { return chartTop + chartZone * 0.5 }
        let normalized = 1.0 - CGFloat((val - valueRange.min) / range)
        return chartTop + normalized * chartZone
    }
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let count = CGFloat(dataPoints.count)
            let columnWidth = count > 0 ? width / count : width
            
            let xPositions = dataPoints.indices.map { i in
                (CGFloat(i) + 0.5) * columnWidth
            }
            let lineYPositions = dataPoints.map { lineY(for: value(for: $0)) }
            
            ZStack(alignment: .topLeading) {
                // Layer 1: Connecting line
                HourlyChartLineShape(
                    pointYValues: AnimatablePointList(values: lineYPositions.map { Double($0) }),
                    pointXPositions: xPositions,
                    gapRadius: 15
                )
                .stroke(lineColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                
                // Layer 3: Data columns
                HStack(spacing: 0) {
                    ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, forecast in
                        let pointY = lineYPositions[index]
                        
                        let pastHour = isPastHour(forecast.hour)
                        ZStack {
                            // Hour label — fixed near top
                            Text(forecast.shortFormattedHour(locale: locale))
                                .font(.avenir(.caption))
                                .foregroundStyle(.secondary)
                                .frame(height: hourLabelHeight)
                                .position(x: columnWidth / 2, y: hourLabelHeight / 2 + 10)
                                .opacity(pastHour ? 0.3 : 1.0)
                            
                            // Icon — above the value
                            Image(systemName: forecast.weatherIcon)
                                .font(.title3)
                                .weatherIconStyle(for: forecast.weatherIcon)
                                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                                .frame(height: iconHeight)
                                .position(x: columnWidth / 2, y: pointY - iconToValue - iconHeight / 2)
                                .opacity(pastHour ? 0.3 : 1.0)
                            
                            // Value text — centered on the line point, offset right so numbers align with icon
                            Text(showCloudCover ? "\(forecast.cloudCoverPercent)%" : tempUnit.display(forecast.temperature))
                                .font(.avenir(.caption, weight: .semibold))
                                .contentTransition(.numericText())
                                .frame(height: valueHeight)
                                .position(x: columnWidth / 2 + 2 , y: pointY)
                                .opacity(pastHour ? 0.3 : 1.0)
                        }
                        .frame(width: columnWidth, height: totalHeight)
                    }
                }
            }
        }
        .frame(height: totalHeight)
        .animation(.smooth(duration: 0.3), value: showCloudCover)
    }
}

struct DayForecastBox: View {
    let dailyForecast: DailyForecast
    let isSelected: Bool
    let cornerRadius: RectangleCornerRadii
    let showCloudCover: Bool
    let cityTimeZone: TimeZone
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    
    init(dailyForecast: DailyForecast, isSelected: Bool, cornerRadius: RectangleCornerRadii = .init(), showCloudCover: Bool = false, cityTimeZone: TimeZone = .current) {
        self.dailyForecast = dailyForecast
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.showCloudCover = showCloudCover
        self.cityTimeZone = cityTimeZone
    }
    
    private var dayOfWeek: String {
        // Use the city's timezone to determine "today" and day-of-week labels
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = cityTimeZone
        let cityToday = cityCalendar.startOfDay(for: Date())
        
        if let date = cityCalendar.date(byAdding: .day, value: dailyForecast.dayOffset, to: cityToday) {
            if dailyForecast.dayOffset == 0 {
                return localizedString("Today", locale: locale)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEE", options: 0, locale: locale)
                formatter.locale = locale
                formatter.timeZone = cityTimeZone
                return formatter.string(from: date)
            }
        }
        return ""
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Weather icon - always shown
            Image(systemName: dailyForecast.weatherIcon)
                .font(.body)
                .weatherIconStyle(for: dailyForecast.weatherIcon)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(height: 22)
            
            // Day of week
            Text(dayOfWeek)
                .font(.avenir(.caption, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(minWidth: 50)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            UnevenRoundedRectangle(cornerRadii: cornerRadius)
                .fill(isSelected ? AppTheme.shared.colors.listCardFill.mix(with: .black, by: 0.25) : AppTheme.shared.colors.listCardFill)
        )
    }
}
#Preview("Weather Detail - London", traits: .portrait) {
    @Previewable @Namespace var namespace
    @Previewable @State var showDetail = true
    
    let london = City(name: "London", country: "England", latitude: 51.5074, longitude: -0.1278)
    
    // Generate hourly forecast for today
    let hourlyForecasts = (0..<24).map { hour -> HourlyForecast in
        let baseTemp = 15.0
        let hourVariation: Double
        if hour < 6 {
            hourVariation = -5.0
        } else if hour < 12 {
            hourVariation = -2.0 + Double(hour - 6) * 0.8
        } else if hour < 16 {
            hourVariation = 3.0
        } else if hour < 20 {
            hourVariation = 1.0 - Double(hour - 16) * 0.6
        } else {
            hourVariation = -3.0
        }
        
        let temp = baseTemp + hourVariation
        
        let symbol: String
        let condition: AppWeatherCondition
        let precipChance: Double
        
        if hour >= 6 && hour < 18 {
            // Daytime with some clouds
            if hour < 10 {
                symbol = "cloud.sun"
                condition = .partlyCloudy
                precipChance = 0.1
            } else if hour < 15 {
                symbol = "sun.max"
                condition = .clear
                precipChance = 0.0
            } else {
                symbol = "cloud.sun"
                condition = .partlyCloudy
                precipChance = 0.2
            }
        } else {
            // Nighttime
            symbol = "cloud.moon"
            condition = .partlyCloudy
            precipChance = 0.15
        }
        
        return HourlyForecast(
            hour: hour,
            temperature: temp,
            symbolName: symbol,
            condition: condition,
            precipitationChance: precipChance,
            cloudCover: Double(condition.estimatedCloudCover) / 100.0
        )
    }
    
    // Generate daily forecasts for 10 days
    let dailyForecasts = (0..<10).map { dayOffset -> DailyForecast in
        let baseTemp = 15.0 + Double.random(in: -3...3)
        
        let symbol: String
        let condition: AppWeatherCondition
        
        switch dayOffset {
        case 0:
            symbol = "cloud.sun"
            condition = .partlyCloudy
        case 1:
            symbol = "sun.max"
            condition = .clear
        case 2:
            symbol = "cloud"
            condition = .cloudy
        case 3:
            symbol = "cloud.rain"
            condition = .rain
        case 4:
            symbol = "cloud.drizzle"
            condition = .drizzle
        default:
            symbol = ["sun.max", "cloud.sun", "cloud", "cloud.rain"].randomElement()!
            condition = [.clear, .partlyCloudy, .cloudy, .rain].randomElement()!
        }
        
        // Generate hourly forecasts for each day
        let dayHourlyForecasts = (0..<24).map { hour -> HourlyForecast in
            let hourVariation = Double.random(in: -4...4)
            let temp = baseTemp + hourVariation
            
            let hourSymbol = (hour >= 6 && hour < 18) ? symbol : "cloud.moon"
            let precipChance = condition == .rain ? Double.random(in: 0.5...0.9) : Double.random(in: 0...0.3)
            
            return HourlyForecast(
                hour: hour,
                temperature: temp,
                symbolName: hourSymbol,
                condition: condition,
                precipitationChance: precipChance,
                cloudCover: Double(condition.estimatedCloudCover) / 100.0
            )
        }
        
        return DailyForecast(
            dayOffset: dayOffset,
            daytimeLow: baseTemp - 3.0,
            daytimeHigh: baseTemp + 3.0,
            symbolName: symbol,
            condition: condition,
            hourlyForecasts: dayOffset == 0 ? hourlyForecasts : dayHourlyForecasts,
            cloudCover: Double(condition.estimatedCloudCover) / 100.0,
            precipitationChance: condition == .rain || condition == .drizzle ? 0.7 : 0.1
        )
    }
    
    let londonWeather = CityWeather(
        city: london,
        condition: .partlyCloudy,
        temperature: 15,
        symbolName: "cloud.sun",
        dailyForecasts: dailyForecasts,
        timeZone: TimeZone(identifier: "Europe/London")!
    )
    
    ZStack {
        // Background
        AppTheme.shared.colors.background
        .ignoresSafeArea()
        
        if showDetail {
            WeatherDetailView(
                cityWeather: londonWeather,
                selectedDayOffset: .constant(0),
                namespace: namespace,
                onDismiss: { },
                onAddCity: { },
                isInSidebar: false,
                previewCurrentHour: 14
            )
        }
    }
}

