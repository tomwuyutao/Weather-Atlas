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
    let onAddCityToList: ((CityListID) -> Void)?
    let availableLists: [CityListID]
    let onDeleteCity: (() -> Void)?
    let onRevealOnMap: (() -> Void)?
    let isInSidebar: Bool
    let showCloudCover: Bool
    var previewCurrentHour: Int? = nil
    var initialChartMetric: ChartMetric? = nil
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) var locale
    @State var internalSelectedDay: Int
    @State var previousDay: Int
    @State var swipeDirection: SwipeDirection = .forward
    @State var isSwipingDays: Bool = false
    
    enum SwipeDirection {
        case forward, backward
    }
    
    enum ChartMetric: Equatable {
        case temperature, feelsLike, cloudCover, precipitation
        case windSpeed, uvIndex, humidity, visibility
    }

    enum ChartTimeRange: Equatable {
        case daytime, entireDay, tenDay
    }
    
    @State var chartMetric: ChartMetric = .temperature
    @State var chartTimeRange: ChartTimeRange = .daytime
    @State var showingChartRangePopover: Bool = false
    @State var showingChartMetricPopover: Bool = false
    @State private var showingCloudCover: Bool = false
    @State private var showingDetailMenu: Bool = false
    @State private var showingAddToListMenu: Bool = false
    @State private var dayScrollHasMore: Bool = true
    @State var chartScrollAtStart: Bool = true
    @State var chartScrollAtEnd: Bool = false
    @State var isHeaderCollapsed: Bool = false
    @State var headerDragOffset: CGFloat = 0
    @State var scrollAtTop: Bool = true
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    var distUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    // Initialize with the day from the map slider
    init(cityWeather: CityWeather, selectedDayOffset: Binding<Int>, namespace: Namespace.ID, onDismiss: @escaping () -> Void, onAddCity: (() -> Void)? = nil, onAddCityToList: ((CityListID) -> Void)? = nil, availableLists: [CityListID] = [], onDeleteCity: (() -> Void)? = nil, onRevealOnMap: (() -> Void)? = nil, isInSidebar: Bool = true, showCloudCover: Bool = false, previewCurrentHour: Int? = nil, initialChartMetric: ChartMetric? = nil) {
        self.cityWeather = cityWeather
        self._selectedDayOffset = selectedDayOffset
        self.namespace = namespace
        self.onDismiss = onDismiss
        self.onAddCity = onAddCity
        self.onAddCityToList = onAddCityToList
        self.availableLists = availableLists
        self.onDeleteCity = onDeleteCity
        self.onRevealOnMap = onRevealOnMap
        self.isInSidebar = isInSidebar
        self.showCloudCover = showCloudCover
        self.previewCurrentHour = previewCurrentHour
        self.initialChartMetric = initialChartMetric
        self._internalSelectedDay = State(initialValue: selectedDayOffset.wrappedValue)
        self._previousDay = State(initialValue: selectedDayOffset.wrappedValue)
        self._chartMetric = State(initialValue: initialChartMetric ?? .temperature)
    }
    
    var forecast: DailyForecast {
        cityWeather.forecast(for: max(0, internalSelectedDay))
    }
    
    /// Whether the "Now" mode is selected (-1), showing current weather
    var isNow: Bool {
        internalSelectedDay == -1
    }
    
    /// For today, show current weather icon; for future days, show forecast icon
    /// Use plain cloud icon when animation shows precipitation
    var detailDisplayIcon: String {
        let baseCondition = isNow ? cityWeather.condition : forecast.condition
        let baseIcon = isNow ? cityWeather.weatherIcon : forecast.weatherIcon
        if baseCondition == .rain || baseCondition == .drizzle || baseCondition == .snow {
            return "cloud.fill"
        }
        return baseIcon
    }
    
    /// For today, show current condition; for future days, show forecast condition
    var detailDisplayCondition: AppWeatherCondition {
        isNow ? cityWeather.condition : forecast.condition
    }
    
    /// Whether it's currently nighttime in this city (outside sunrise-sunset)
    var isCurrentlyNight: Bool {
        guard isNow,
              let sunrise = forecast.sunrise,
              let sunset = forecast.sunset else { return false }
        let now = Date()
        return now < sunrise || now > sunset
    }
    
    var goingForward: Bool {
        internalSelectedDay >= previousDay
    }
    
    var headerBackgroundColor: Color {
        let theme = AppTheme.shared.colors
        let condition = detailDisplayCondition
        
        // At night, always use moon purple
        if isCurrentlyNight {
            return theme.moonIconColor
        }
        
        switch condition {
        case .rain: return theme.dotRain
        case .drizzle: return theme.dotDrizzle
        case .snow, .cloudy, .wind: return Color(hex: 0x9ABCCE)
        case .partlyCloudy:
            // If WeatherKit gave a plain cloud icon (no sun), treat as overcast
            return detailDisplayIcon == "cloud.fill" ? Color(hex: 0x9ABCCE) : Color(hex: 0xF0B830)
        default:
            return detailDisplayIcon == "cloud.fill" ? Color(hex: 0x9ABCCE) : condition.dotColor
        }
    }

    var chartLineColor: Color {
        switch chartMetric {
        case .temperature:   return Color(hex: 0xE8536B)
        case .feelsLike:     return Color(hex: 0xED8988)
        case .cloudCover:    return Color(hex: 0x9ABCCE)
        case .precipitation: return Color(hex: 0x57D3E5)
        case .windSpeed:     return Color(hex: 0xFDA409)
        case .uvIndex:       return Color(hex: 0xFB4368)
        case .humidity:      return Color(hex: 0xBE9AED)
        case .visibility:    return Color(hex: 0x1579C7)
        }
    }

    var chartMetricIcon: String {
        switch chartMetric {
        case .temperature:   return "thermometer.medium"
        case .feelsLike:     return "thermometer.variable.and.figure"
        case .cloudCover:    return "cloud"
        case .precipitation: return "drop.fill"
        case .windSpeed:     return "wind"
        case .uvIndex:       return "sun.max.fill"
        case .humidity:      return "humidity.fill"
        case .visibility:    return "eye"
        }
    }

    var chartMetricLabel: String {
        switch chartMetric {
        case .temperature:   return localizedString("Temperature", locale: locale)
        case .feelsLike:     return localizedString("Feels Like", locale: locale)
        case .cloudCover:    return localizedString("Cloud Cover", locale: locale)
        case .precipitation: return localizedString("Precipitation", locale: locale)
        case .windSpeed:     return localizedString("Wind Speed", locale: locale)
        case .uvIndex:       return localizedString("UV Index", locale: locale)
        case .humidity:      return localizedString("Humidity", locale: locale)
        case .visibility:    return localizedString("Visibility", locale: locale)
        }
    }

    var chartMetricCurrentValue: String {
        switch chartMetric {
        case .temperature:
            return isNow
                ? tempUnit.display(cityWeather.temperature)
                : tempUnit.displaySlash(low: forecast.dailyLow, high: forecast.dailyHigh)
        case .feelsLike:
            if isNow {
                return cityWeather.currentFeelsLike.map { tempUnit.display($0) } ?? "—"
            } else {
                if let low = forecast.feelsLikeLow, let high = forecast.feelsLikeHigh {
                    return tempUnit.displaySlash(low: low, high: high)
                }
                return "—"
            }
        case .cloudCover:
            return (isNow ? cityWeather.currentCloudCover : forecast.cloudCover).map { "\(Int($0 * 100))%" } ?? "—"
        case .precipitation:
            if isNow {
                return [.rain, .drizzle, .snow].contains(cityWeather.condition) ? "100%" : "0%"
            }
            return forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "—"
        case .windSpeed:
            return (isNow ? cityWeather.currentWindSpeed : forecast.windSpeed).map { distUnit.displayWindSpeed($0) } ?? "—"
        case .uvIndex:
            return (isNow ? cityWeather.currentUVIndex : forecast.uvIndex).map { "\($0)" } ?? "—"
        case .humidity:
            return (isNow ? cityWeather.currentHumidity : forecast.maxHumidity).map { "\(Int($0 * 100))%" } ?? "—"
        case .visibility:
            return (isNow ? cityWeather.currentVisibility : forecast.maxVisibility).map { distUnit.display($0) } ?? "—"
        }
    }

    var chartMetricPopoverContent: some View {
        let allMetrics: [(ChartMetric, String, String)] = [
            (.temperature, "thermometer.medium", localizedString("Temperature", locale: locale)),
            (.feelsLike, "thermometer.variable.and.figure", localizedString("Feels Like", locale: locale)),
            (.cloudCover, "cloud", localizedString("Cloud Cover", locale: locale)),
            (.precipitation, "drop.fill", localizedString("Precipitation", locale: locale)),
            (.windSpeed, "wind", localizedString("Wind Speed", locale: locale)),
            (.uvIndex, "sun.max.fill", localizedString("UV Index", locale: locale)),
            (.humidity, "humidity.fill", localizedString("Humidity", locale: locale)),
            (.visibility, "eye", localizedString("Visibility", locale: locale)),
        ]

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(allMetrics, id: \.0) { metric, icon, label in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        chartMetric = metric
                    }
                    showingChartMetricPopover = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: icon)
                            .font(.system(size: 13))
                            .frame(width: 18)
                        Text(label)
                            .font(.avenir(.body, weight: chartMetric == metric ? .bold : .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        if chartMetric == metric {
                            Circle()
                                .fill(AppTheme.shared.colors.accent)
                                .frame(width: 6, height: 6)
                                .frame(width: 13)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 220)
        .themedPopoverBackground()
    }

    var chartTimeRangePopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    chartTimeRange = .daytime
                }
                showingChartRangePopover = false
            } label: {
                HStack(spacing: 12) {
                    Text(localizedString("Daytime", locale: locale))
                        .font(.avenir(.body, weight: chartTimeRange == .daytime ? .bold : .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    if chartTimeRange == .daytime {
                        Circle()
                            .fill(AppTheme.shared.colors.accent)
                            .frame(width: 6, height: 6)
                            .frame(width: 13)
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    chartTimeRange = .entireDay
                }
                showingChartRangePopover = false
            } label: {
                HStack(spacing: 12) {
                    Text(localizedString("Entire Day", locale: locale))
                        .font(.avenir(.body, weight: chartTimeRange == .entireDay ? .bold : .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    if chartTimeRange == .entireDay {
                        Circle()
                            .fill(AppTheme.shared.colors.accent)
                            .frame(width: 6, height: 6)
                            .frame(width: 13)
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    chartTimeRange = .tenDay
                }
                showingChartRangePopover = false
            } label: {
                HStack(spacing: 12) {
                    Text(localizedString("10 Days", locale: locale))
                        .font(.avenir(.body, weight: chartTimeRange == .tenDay ? .bold : .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    if chartTimeRange == .tenDay {
                        Circle()
                            .fill(AppTheme.shared.colors.accent)
                            .frame(width: 6, height: 6)
                            .frame(width: 13)
                    }
                }
                .padding(.leading, 24)
                .padding(.trailing, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(width: 210)
        .themedPopoverBackground()
    }

    var isPopup: Bool {
        false
    }

    var expandedHeaderHeight: CGFloat { 270 }
    var collapsedHeaderHeight: CGFloat { 105 }

    var currentHeaderHeight: CGFloat {
        let base: CGFloat = isHeaderCollapsed ? collapsedHeaderHeight : expandedHeaderHeight
        let clamped = max(collapsedHeaderHeight, base + headerDragOffset * 0.4)
        return clamped
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Weather condition color block — fixed at top, animates height
            headerBackgroundBlock

            // Floating header (iOS only) — outside ScrollView so scroll doesn't move it
            floatingHeader

            // Main content card
            ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: isPopup ? 24 : 16) {
                if !isPopup {
                    Color.clear.frame(height: currentHeaderHeight + 20)
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isHeaderCollapsed)
                }

                if isPopup {
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
                                if !detailDisplayIcon.contains("moon") {
                                    WeatherEffectOverlay(condition: detailDisplayCondition, isCompact: false, iconHeight: 56)
                                        .id("detail-effect-\(internalSelectedDay)-\(detailDisplayCondition.displayName)")
                                }
                            }
                            .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                            .padding(.top, 28)

                        if isNow {
                            // Now: current temperature only, no high/low
                            Text(tempUnit.display(cityWeather.temperature))
                                .font(.avenir(.largeTitle, weight: .bold))
                                .dynamicTypeSize(...DynamicTypeSize.large)
                                .contentTransition(.numericText())
                                .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                                .padding(.top, 14)
                                .padding(.trailing, 4)
                                .offset(x: 5)
                        } else {
                            // Today/future: high with low at 60% opacity
                            HStack(alignment: .firstTextBaseline, spacing: 0) {
                                Text(tempUnit.display(forecast.dailyHigh))
                                    .font(.avenir(.largeTitle, weight: .bold))
                                Text(" ")
                                    .font(.avenir(.largeTitle, weight: .bold))
                                Text(tempUnit.display(forecast.dailyLow))
                                    .font(.avenir(.largeTitle, weight: .bold))
                                    .opacity(0.6)
                            }
                            .dynamicTypeSize(...DynamicTypeSize.large)
                            .contentTransition(.numericText())
                            .animation(.smooth(duration: 0.3), value: internalSelectedDay)
                            .padding(.top, 14)
                            .padding(.trailing, 4)
                            .offset(x: 5)
                        }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.large)
                }

                // 10-day forecast horizontal scroll
                if !isPopup {
                    let lastIndex = cityWeather.dailyForecasts.count - 1
                    ScrollViewReader { scrollProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            // "Now" box before daily forecasts
                            let r: CGFloat = 8
                            VStack(spacing: 4) {
                                Image(systemName: cityWeather.weatherIcon)
                                    .font(.body)
                                    .weatherIconStyle(for: cityWeather.weatherIcon)
                                    .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                                    .frame(height: 22)
                                Text(localizedString("Now", locale: locale))
                                    .font(.avenir(.caption, weight: internalSelectedDay == -1 ? .semibold : .medium))
                                    .foregroundStyle(internalSelectedDay == -1 ? .primary : .secondary)
                            }
                            .frame(minWidth: 50)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                UnevenRoundedRectangle(cornerRadii: .init(topLeading: r, bottomLeading: r))
                                    .fill(internalSelectedDay == -1 ? AppTheme.shared.colors.listCardFill.mix(with: .black, by: colorScheme == .dark ? 0.25 : 0.06) : AppTheme.shared.colors.listCardFill)
                            )
                            .id(-1)
                            .onTapGesture {
                                swipeDirection = -1 >= internalSelectedDay ? .forward : .backward
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    internalSelectedDay = -1
                                }
                            }
                            
                            ForEach(Array(cityWeather.dailyForecasts.enumerated()), id: \.element.id) { index, dailyForecast in
                                let cr = RectangleCornerRadii(
                                    topLeading: 0,
                                    bottomLeading: 0,
                                    bottomTrailing: index == lastIndex ? r : 0,
                                    topTrailing: index == lastIndex ? r : 0
                                )
                                DayForecastBox(
                                    dailyForecast: dailyForecast,
                                    isSelected: internalSelectedDay == dailyForecast.dayOffset,
                                    cornerRadius: cr,
                                    showCloudCover: showCloudCover,
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            scrollProxy.scrollTo(newDay, anchor: .center)
                        }
                    }
                    }
                    .padding(.horizontal, 8)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { value in
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    isSwipingDays = true
                                }
                            }
                            .onEnded { _ in isSwipingDays = false }
                    )
                }

                // Chart card with switchers (WeatherDetailView+ChartCard.swift)
                chartCard

                // Stats grid (WeatherDetailView+StatsGrid.swift)
                statsGrid

                // Sun arc card — only show when sunrise/sunset data is available
                if let sunrise = forecast.sunrise, let sunset = forecast.sunset {
                    SunArcCard(
                        sunrise: sunrise,
                        sunset: sunset,
                        cityTimeZone: cityWeather.timeZone
                    )
                    .padding(.horizontal, 8)
                }

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
                                    .frame(width: 44, height: 44)
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
                                                Text(localizedString("Reveal on Map", locale: locale))
                                                    .font(.avenir(.body, weight: .medium))
                                                    .foregroundStyle(.primary)
                                                Spacer()
                                            }
                                            .padding(.leading, 24)
                                            .padding(.trailing, 16)
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
                                                Text(localizedString("Delete City", locale: locale))
                                                    .font(.avenir(.body, weight: .medium))
                                                    .foregroundStyle(AppTheme.shared.colors.destructive)
                                                Spacer()
                                            }
                                            .padding(.leading, 24)
                                            .padding(.trailing, 16)
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
                                .frame(width: 44, height: 44)
                                .themedGlass(in: .circle)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .named("detailScroll")).minY) { _, newY in
                            scrollAtTop = newY >= -1
                        }
                }
            )
            } // ScrollView
            .coordinateSpace(name: "detailScroll")
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollDisabled(!isPopup && !isHeaderCollapsed)
            .frame(maxWidth: isPopup ? 340 : .infinity)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .global)
                    .onEnded { value in
                        guard !isPopup else { return }
                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        guard dy > dx else { return }  // vertical-dominant swipe only
                        let vy = value.velocity.height
                        let ty = value.translation.height
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            if !isHeaderCollapsed && (ty < -40 || vy < -300) {
                                isHeaderCollapsed = true
                            } else if isHeaderCollapsed && scrollAtTop && (ty > 40 || vy > 300) {
                                isHeaderCollapsed = false
                            }
                        }
                    }
            )



        }
        .frame(maxHeight: isPopup ? nil : .infinity, alignment: .top)
        .onAppear {
            isHeaderCollapsed = false
            headerDragOffset = 0
            scrollAtTop = true
        }
        .onChange(of: cityWeather.city.name) {
            isHeaderCollapsed = false
            headerDragOffset = 0
            scrollAtTop = true
        }
        .contentShape(Rectangle())
        .matchedGeometryEffect(id: isPopup ? (isInSidebar ? "sidebar-\(cityWeather.id)" : "marker-\(cityWeather.id)") : "", in: namespace, isSource: isPopup)
        .transition(isPopup ? .scale(scale: 0.5).combined(with: .opacity) : .identity)
    }
    
    private var forecastDateText: String {
        // Use the city's timezone so day labels match the city's local date
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = cityWeather.timeZone
        let cityToday = cityCalendar.startOfDay(for: Date())
        
        if internalSelectedDay == -1 {
            return localizedString("Now", locale: locale)
        }
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
    var chartMetric: WeatherDetailView.ChartMetric = .temperature
    var dayOffset: Int = 0
    var cityTimeZone: TimeZone = .current
    var previewCurrentHour: Int? = nil
    var lineColor: Color = AppTheme.shared.colors.destructive
    var showAllHours: Bool = false
    
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    
    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }
    
    private var currentCityHour: Int? {
        guard dayOffset == 0 || dayOffset == -1 else { return nil }
        if let override = previewCurrentHour { return override }
        var calendar = Calendar.current
        calendar.timeZone = cityTimeZone
        return calendar.component(.hour, from: Date())
    }
    
    private func isPastHour(_ hour: Int) -> Bool {
        guard let currentHour = currentCityHour else { return false }
        return hour < currentHour
    }
    
    private let totalHeight: CGFloat = 250
    private let hourLabelHeight: CGFloat = 20  // fixed hour label at top
    private let topPadding: CGFloat = 4        // space below hour label
    private let iconHeight: CGFloat = 26       // icon sits just below hour label
    private let iconBottomPadding: CGFloat = 20 // gap between icon bottom and chart top
    private let valueHeight: CGFloat = 20      // height of value text (sits on line)
    
    // Chart zone starts below the fixed header (hour + icon), value text straddles line
    private var chartTop: CGFloat { hourLabelHeight + topPadding + iconHeight + iconBottomPadding }
    private var chartBottom: CGFloat { totalHeight - valueHeight - 14 }
    private var chartZone: CGFloat { chartBottom - chartTop }
    
    private var dataPoints: [HourlyForecast] {
        if showAllHours {
            return hourlyForecasts.sorted { $0.hour < $1.hour }
        }
        return hourlyForecasts.filter { [7, 9, 11, 13, 15, 17, 19].contains($0.hour) }
    }
    
    private func chartValueText(for forecast: HourlyForecast) -> String {
        switch chartMetric {
        case .temperature:   return tempUnit.display(forecast.temperature)
        case .feelsLike:     return forecast.apparentTemperature.map { tempUnit.display($0) } ?? "—"
        case .cloudCover:    return forecast.cloudCoverPercent.map { "\($0)%" } ?? "—"
        case .precipitation: return forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "—"
        case .windSpeed:     return forecast.windSpeed.map { "\(Int($0))" } ?? "—"
        case .uvIndex:       return forecast.uvIndex.map { "\($0)" } ?? "—"
        case .humidity:      return forecast.humidity.map { "\(Int($0 * 100))%" } ?? "—"
        case .visibility:    return forecast.visibility.map { "\(Int($0))" } ?? "—"
        }
    }
    
    private func value(for forecast: HourlyForecast) -> Double {
        switch chartMetric {
        case .temperature:      return forecast.temperature
        case .feelsLike:        return forecast.apparentTemperature ?? forecast.temperature
        case .cloudCover:       return Double(forecast.cloudCoverPercent ?? 0)
        case .precipitation:    return (forecast.precipitationChance ?? 0) * 100
        case .windSpeed:        return forecast.windSpeed ?? 0
        case .uvIndex:          return Double(forecast.uvIndex ?? 0)
        case .humidity:         return (forecast.humidity ?? 0) * 100
        case .visibility:       return forecast.visibility ?? 10
        }
    }
    
    private var valueRange: (min: Double, max: Double) {
        switch chartMetric {
        case .cloudCover, .precipitation, .humidity:
            return (0, 100)
        case .uvIndex:
            return (0, 11)
        case .windSpeed:
            return (0, 100)
        case .visibility:
            let vals = dataPoints.map { value(for: $0) }
            let maxV = vals.max() ?? 30
            return (0, max(30, maxV + 5))
        case .temperature, .feelsLike:
            let vals = dataPoints.map { value(for: $0) }
            let minV = vals.min() ?? 10
            let maxV = vals.max() ?? 20
            let padding = max((maxV - minV) * 0.25, 2.0)
            return (minV - padding, maxV + padding)
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
        if dataPoints.isEmpty {
            // No hourly data available for this day
            VStack(spacing: 8) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("No hourly data")
                    .font(.avenir(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: totalHeight)
            .frame(maxWidth: .infinity)
        } else {
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
                    gapRadius: 0
                )
                .stroke(lineColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                // Layer 2: Dots on line points
                ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, forecast in
                    Circle()
                        .fill(lineColor)
                        .frame(width: 10, height: 10)
                        .position(x: xPositions[index], y: lineYPositions[index])
                }

                // Layer 3: Current time vertical indicator line (behind text)
                if let currentHour = currentCityHour {
                    let hours = dataPoints.map { $0.hour }
                    let lineTop = chartTop - 4
                    let lineBottom = chartBottom + valueHeight
                    let lineHeight = lineBottom - lineTop
                    let lineCenterY = lineTop + lineHeight / 2

                    if let lastIdx = hours.lastIndex(where: { $0 <= currentHour }),
                       lastIdx < hours.count - 1 {
                        let h0 = CGFloat(hours[lastIdx])
                        let h1 = CGFloat(hours[lastIdx + 1])
                        let fraction = h1 > h0 ? CGFloat(currentHour - hours[lastIdx]) / (h1 - h0) : 0
                        let nowX = xPositions[lastIdx] + fraction * (xPositions[lastIdx + 1] - xPositions[lastIdx])
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 3, height: lineHeight)
                            .position(x: nowX, y: lineCenterY)
                            .opacity(0.5)
                    } else if let firstHour = hours.first, currentHour < firstHour {
                        let nowX = xPositions[0] * CGFloat(currentHour) / CGFloat(firstHour)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 3, height: lineHeight)
                            .position(x: max(nowX, 4), y: lineCenterY)
                            .opacity(0.5)
                    }
                }

                // Layer 4: Data columns
                HStack(spacing: 0) {
                    ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, forecast in
                        let pointY = lineYPositions[index]
                        let pastHour = isPastHour(forecast.hour)
                        let iconY = hourLabelHeight + topPadding + iconHeight / 2 + 10
                        ZStack {
                            // Hour label — fixed at top
                            Text(forecast.shortFormattedHour(locale: locale))
                                .font(.avenir(.subheadline))
                                .foregroundStyle(AppTheme.shared.colors.primaryText)
                                .frame(height: hourLabelHeight)
                                .position(x: columnWidth / 2, y: hourLabelHeight / 2 + 10)
                                .opacity(pastHour ? 0.3 : 1.0)

                            // Icon — fixed just below hour label
                            Image(systemName: forecast.weatherIcon)
                                .font(.system(size: 17))
                                .weatherIconStyle(for: forecast.weatherIcon)
                                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                                .frame(height: iconHeight)
                                .position(x: columnWidth / 2, y: iconY)
                                .opacity(pastHour ? 0.3 : 1.0)

                            // Value text — sits below the dot on the line
                            Text(chartValueText(for: forecast))
                                .font(.avenir(.footnote, weight: .semibold))
                                .foregroundStyle(AppTheme.shared.colors.primaryText)
                                .contentTransition(.numericText())
                                .frame(height: valueHeight)
                                .position(x: columnWidth / 2 + 2, y: pointY + valueHeight * 0.85 + 2)
                                .opacity(pastHour ? 0.3 : 1.0)
                        }
                        .frame(width: columnWidth, height: totalHeight)
                    }
                }
            }
        }
        .frame(height: totalHeight)
        .animation(.smooth(duration: 0.3), value: chartMetric)
        } // else (has data)
    }
}

// MARK: - 10-Day timeline chart

struct DailyTimelineChart: View {
    let dailyForecasts: [DailyForecast]
    var chartMetric: WeatherDetailView.ChartMetric = .temperature
    var selectedDayOffset: Int = 0
    var cityTimeZone: TimeZone = .current
    var lineColor: Color = AppTheme.shared.colors.destructive

    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    private let totalHeight: CGFloat = 250
    private let dayLabelHeight: CGFloat = 20
    private let topPadding: CGFloat = 4
    private let iconHeight: CGFloat = 26
    private let iconBottomPadding: CGFloat = 20
    private let valueHeight: CGFloat = 20

    private var chartTop: CGFloat { dayLabelHeight + topPadding + iconHeight + iconBottomPadding }
    private var chartBottom: CGFloat { totalHeight - valueHeight - 14 }
    private var chartZone: CGFloat { chartBottom - chartTop }

    private var dataPoints: [DailyForecast] {
        dailyForecasts.sorted { $0.dayOffset < $1.dayOffset }
    }

    private func dayLabel(for forecast: DailyForecast) -> String {
        var cityCalendar = Calendar.current
        cityCalendar.timeZone = cityTimeZone
        let cityToday = cityCalendar.startOfDay(for: Date())
        if let date = cityCalendar.date(byAdding: .day, value: forecast.dayOffset, to: cityToday) {
            if forecast.dayOffset == 0 {
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

    private func value(for forecast: DailyForecast) -> Double {
        switch chartMetric {
        case .temperature:      return forecast.dailyHigh
        case .feelsLike:        return forecast.feelsLikeHigh ?? forecast.dailyHigh
        case .cloudCover:       return (forecast.cloudCover ?? 0) * 100
        case .precipitation:    return (forecast.precipitationChance ?? 0) * 100
        case .windSpeed:        return forecast.windSpeed ?? 0
        case .uvIndex:          return Double(forecast.uvIndex ?? 0)
        case .humidity:         return (forecast.maxHumidity ?? 0) * 100
        case .visibility:       return forecast.maxVisibility ?? 10
        }
    }

    private func chartValueText(for forecast: DailyForecast) -> String {
        switch chartMetric {
        case .temperature:   return tempUnit.display(forecast.dailyHigh)
        case .feelsLike:     return forecast.feelsLikeHigh.map { tempUnit.display($0) } ?? "—"
        case .cloudCover:    return forecast.cloudCover.map { "\(Int($0 * 100))%" } ?? "—"
        case .precipitation: return forecast.precipitationChance.map { "\(Int($0 * 100))%" } ?? "—"
        case .windSpeed:     return forecast.windSpeed.map { "\(Int($0))" } ?? "—"
        case .uvIndex:       return forecast.uvIndex.map { "\($0)" } ?? "—"
        case .humidity:      return forecast.maxHumidity.map { "\(Int($0 * 100))%" } ?? "—"
        case .visibility:    return forecast.maxVisibility.map { "\(Int($0))" } ?? "—"
        }
    }

    private var valueRange: (min: Double, max: Double) {
        switch chartMetric {
        case .cloudCover, .precipitation, .humidity:
            return (0, 100)
        case .uvIndex:
            return (0, 11)
        case .windSpeed:
            return (0, 100)
        case .visibility:
            let vals = dataPoints.map { value(for: $0) }
            let maxV = vals.max() ?? 30
            return (0, max(30, maxV + 5))
        case .temperature, .feelsLike:
            let vals = dataPoints.map { value(for: $0) }
            let minV = vals.min() ?? 10
            let maxV = vals.max() ?? 20
            let padding = max((maxV - minV) * 0.25, 2.0)
            return (minV - padding, maxV + padding)
        }
    }

    private func lineY(for val: Double) -> CGFloat {
        let range = valueRange.max - valueRange.min
        guard range > 0 else { return chartTop + chartZone * 0.5 }
        let normalized = 1.0 - CGFloat((val - valueRange.min) / range)
        return chartTop + normalized * chartZone
    }

    var body: some View {
        if dataPoints.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("No daily data")
                    .font(.avenir(.subheadline, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: totalHeight)
            .frame(maxWidth: .infinity)
        } else {
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
                    gapRadius: 0
                )
                .stroke(lineColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                // Layer 2: Dots on line points
                ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, _ in
                    Circle()
                        .fill(lineColor)
                        .frame(width: 10, height: 10)
                        .position(x: xPositions[index], y: lineYPositions[index])
                }

                // Layer 3: Vertical indicator line on selected day
                if let selectedIndex = dataPoints.firstIndex(where: {
                    // "Now" (-1) maps to today (dayOffset 0)
                    $0.dayOffset == (selectedDayOffset == -1 ? 0 : selectedDayOffset)
                }) {
                    let lineTop = chartTop - 4
                    let lineBottom = chartBottom + valueHeight
                    let lineHeight = lineBottom - lineTop
                    let lineCenterY = lineTop + lineHeight / 2
                    let nowX = xPositions[selectedIndex]
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 3, height: lineHeight)
                        .position(x: nowX, y: lineCenterY)
                        .opacity(0.5)
                }

                // Layer 4: Data columns
                HStack(spacing: 0) {
                    ForEach(Array(dataPoints.enumerated()), id: \.element.id) { index, forecast in
                        let pointY = lineYPositions[index]
                        let iconY = dayLabelHeight + topPadding + iconHeight / 2 + 10
                        ZStack {
                            // Day label — fixed at top
                            Text(dayLabel(for: forecast))
                                .font(.avenir(.subheadline))
                                .foregroundStyle(AppTheme.shared.colors.primaryText)
                                .frame(height: dayLabelHeight)
                                .position(x: columnWidth / 2, y: dayLabelHeight / 2 + 10)

                            // Icon — fixed just below day label
                            Image(systemName: forecast.weatherIcon)
                                .font(.system(size: 17))
                                .weatherIconStyle(for: forecast.weatherIcon)
                                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                                .frame(height: iconHeight)
                                .position(x: columnWidth / 2, y: iconY)

                            // Value text — sits below the dot on the line
                            Text(chartValueText(for: forecast))
                                .font(.avenir(.footnote, weight: .semibold))
                                .foregroundStyle(AppTheme.shared.colors.primaryText)
                                .contentTransition(.numericText())
                                .frame(height: valueHeight)
                                .position(x: columnWidth / 2 + 2, y: pointY + valueHeight * 0.85 + 2)
                        }
                        .frame(width: columnWidth, height: totalHeight)
                    }
                }
            }
        }
        .frame(height: totalHeight)
        .animation(.smooth(duration: 0.3), value: chartMetric)
        } // else (has data)
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
                .fill(isSelected ? AppTheme.shared.colors.listCardFill.mix(with: .black, by: colorScheme == .dark ? 0.25 : 0.06) : AppTheme.shared.colors.listCardFill)
        )
    }
}

// MARK: - Weather Stat Card

struct WeatherStatCard: View {
    let label: String
    let value: String
    var valueOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 10) {
            Text(label)
                .font(.avenir(.footnote, weight: .medium))
                .foregroundStyle(AppTheme.shared.colors.secondaryText)
            Text(value)
                .font(.avenir(.title2, weight: .semibold))
                .foregroundStyle(AppTheme.shared.colors.primaryText)
                .contentTransition(.numericText())
                .offset(x: valueOffset)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 110)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.shared.colors.listCardFill)
        )
    }
}

// MARK: - Sun Arc Card

struct SunArcCard: View {
    let sunrise: Date
    let sunset: Date
    let cityTimeZone: TimeZone
    
    private var now: Date { Date() }
    
    /// Progress 0...1 of current time between sunrise and sunset. Clamped to 0...1.
    private var sunProgress: Double {
        let total = sunset.timeIntervalSince(sunrise)
        guard total > 0 else { return 0.5 }
        return max(0, min(1, now.timeIntervalSince(sunrise) / total))
    }
    
    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        f.timeZone = cityTimeZone
        return f
    }
    
    var body: some View {
        let sunColor = AppTheme.shared.colors.dotSun

        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            // Label area: inset + label width determine arc span
            let labelInset: CGFloat = 16
            let labelWidth: CGFloat = 52  // approx width of "icon + time" side by side
            // Arc endpoints at centre of each label
            let startX = labelInset + labelWidth / 2
            let endX   = width - labelInset - labelWidth / 2
            // Baseline for arc endpoints — leaves room for labels below
            let baseY: CGFloat = height - 50
            // Arc peak height — flat elliptical feel
            let peakY: CGFloat = 6
            // Bézier control point: directly above the midpoint at peakY
            let ctrlX = width / 2
            let ctrlY = peakY

            // Sun icon fixed at arc midpoint (t = 0.5)
            let sunCentreX = 0.25 * startX + 0.5 * ctrlX + 0.25 * endX
            let sunCentreY = 0.25 * baseY  + 0.5 * ctrlY  + 0.25 * baseY

            ZStack(alignment: .bottom) {
                // ---- Arc canvas (always full yellow) ----
                Canvas { context, _ in
                    let stroke = StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    var arcPath = Path()
                    arcPath.move(to: CGPoint(x: startX, y: baseY))
                    arcPath.addQuadCurve(
                        to: CGPoint(x: endX, y: baseY),
                        control: CGPoint(x: ctrlX, y: ctrlY)
                    )
                    context.stroke(arcPath, with: .color(sunColor), style: stroke)
                }
                .frame(width: width, height: height)

                // ---- Sun icon (fixed at arc centre, circle bg splits the line) ----
                ZStack {
                    Circle()
                        .fill(AppTheme.shared.colors.listCardFill)
                        .frame(width: 44, height: 44)
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(sunColor)
                }
                .position(x: sunCentreX, y: sunCentreY)

                // ---- Time labels (icon + time horizontally, centred in bottom strip) ----
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(sunColor)
                        Text(timeFormatter.string(from: sunrise))
                            .font(.avenir(.footnote, weight: .medium))
                            .foregroundStyle(AppTheme.shared.colors.primaryText)
                    }
                    Spacer()
                    HStack(spacing: 5) {
                        Text(timeFormatter.string(from: sunset))
                            .font(.avenir(.footnote, weight: .medium))
                            .foregroundStyle(AppTheme.shared.colors.primaryText)
                        Image(systemName: "sunset.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(sunColor)
                    }
                }
                .padding(.horizontal, labelInset)
                .padding(.bottom, 24)
            }
        }
        .frame(height: 110)
        .padding(.horizontal, 8)
        .background(AppTheme.shared.colors.listCardFill, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            apparentTemperature: temp - 2.0,
            symbolName: symbol,
            condition: condition,
            precipitationChance: precipChance,
            cloudCover: Double(condition.estimatedCloudCover) / 100.0,
            windSpeed: Double.random(in: 5...35),
            uvIndex: (hour >= 6 && hour < 18) ? Int.random(in: 1...8) : 0,
            humidity: Double.random(in: 0.3...0.9),
            visibility: Double.random(in: 5...25)
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
                apparentTemperature: temp - 2.0,
                symbolName: hourSymbol,
                condition: condition,
                precipitationChance: precipChance,
                cloudCover: Double(condition.estimatedCloudCover) / 100.0,
                windSpeed: Double.random(in: 5...35),
                uvIndex: (hour >= 6 && hour < 18) ? Int.random(in: 1...8) : 0,
                humidity: Double.random(in: 0.3...0.9),
                visibility: Double.random(in: 5...25)
            )
        }
        
        // Mock sunrise/sunset: 6:30 AM and 6:30 PM local time
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let mockSunrise = calendar.date(byAdding: .init(hour: 6, minute: 30), to: today)
        let mockSunset = calendar.date(byAdding: .init(hour: 18, minute: 30), to: today)
        return DailyForecast(
            dayOffset: dayOffset,
            dailyLow: baseTemp - 3.0,
            dailyHigh: baseTemp + 3.0,
            symbolName: symbol,
            condition: condition,
            hourlyForecasts: dayOffset == 0 ? hourlyForecasts : dayHourlyForecasts,
            cloudCover: Double(condition.estimatedCloudCover) / 100.0,
            precipitationChance: condition == .rain || condition == .drizzle ? 0.7 : 0.1,
            visibility: dayOffset == 0 ? 15.0 : nil,
            feelsLikeLow: baseTemp - 5.0,
            feelsLikeHigh: baseTemp + 1.0,
            humidity: dayOffset == 0 ? 0.65 : nil,
            windSpeed: Double.random(in: 5...40),
            uvIndex: Int.random(in: 0...11),
            maxHumidity: Double.random(in: 0.3...0.95),
            maxVisibility: Double.random(in: 5...30),
            sunrise: mockSunrise,
            sunset: mockSunset
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

