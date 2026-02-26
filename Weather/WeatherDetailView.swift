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
    let selectedDayOffset: Int
    let namespace: Namespace.ID
    let onDismiss: () -> Void
    let onAddCity: (() -> Void)?
    let isInSidebar: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var internalSelectedDay: Int
    
    // Initialize with the day from the map slider
    init(cityWeather: CityWeather, selectedDayOffset: Int, namespace: Namespace.ID, onDismiss: @escaping () -> Void, onAddCity: (() -> Void)? = nil, isInSidebar: Bool = true) {
        self.cityWeather = cityWeather
        self.selectedDayOffset = selectedDayOffset
        self.namespace = namespace
        self.onDismiss = onDismiss
        self.onAddCity = onAddCity
        self.isInSidebar = isInSidebar
        self._internalSelectedDay = State(initialValue: selectedDayOffset)
    }
    
    private var forecast: DailyForecast {
        cityWeather.forecast(for: internalSelectedDay)
    }
    
    var body: some View {
        ZStack {
            // Main content card
            VStack(spacing: 26) {
                // Header
                VStack(alignment: .center, spacing: 7) {
                    Text(cityWeather.city.name)
                        .font(.title)
                        .fontWeight(.semibold)
                    
                    Text(forecastDateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .id("date-\(internalSelectedDay)") // Force SwiftUI to treat this as a new view
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                .clipped() // Clip the header transitions
                
                // Horizontal timeline forecast section
                HStack(spacing: 1) {
                    ForEach(forecast.hourlyForecasts.filter { [6, 9, 12, 15, 18, 21].contains($0.hour) }) { hourlyForecast in
                        TimelineForecastColumn(hourlyForecast: hourlyForecast)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 18)
                .id("hourly-\(internalSelectedDay)") // Force SwiftUI to treat this as a new view when day changes
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .clipped() // Clip the hourly forecast transitions
                
                // 10-day forecast grid
                VStack(spacing: 0) {
                    // First row - 5 days
                    HStack(spacing: 0) {
                        ForEach(Array(cityWeather.dailyForecasts.prefix(5).enumerated()), id: \.element.id) { index, dailyForecast in
                            DayForecastBox(
                                dailyForecast: dailyForecast,
                                isSelected: internalSelectedDay == dailyForecast.dayOffset,
                                cornerRadius: .init(
                                    topLeading: index == 0 ? 8 : 0,
                                    topTrailing: index == 4 ? 8 : 0
                                )
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    internalSelectedDay = dailyForecast.dayOffset
                                }
                            }
                        }
                    }
                    
                    // Second row - 5 days
                    HStack(spacing: 0) {
                        ForEach(Array(cityWeather.dailyForecasts.dropFirst(5).prefix(5).enumerated()), id: \.element.id) { index, dailyForecast in
                            DayForecastBox(
                                dailyForecast: dailyForecast,
                                isSelected: internalSelectedDay == dailyForecast.dayOffset,
                                cornerRadius: .init(
                                    bottomLeading: index == 0 ? 8 : 0,
                                    bottomTrailing: index == 4 ? 8 : 0
                                )
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    internalSelectedDay = dailyForecast.dayOffset
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 36)
            .frame(maxWidth: 340)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 26))
            .clipShape(RoundedRectangle(cornerRadius: 26)) // Clip the entire content to the rounded rectangle
            .shadow(color: .black.opacity(0.3), radius: 20)
            .overlay(alignment: .topLeading) {
                // Add button in upper left corner (if city is not in sidebar)
                if !isInSidebar, let addAction = onAddCity {
                    Button {
                        addAction()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                }
            }
            .overlay(alignment: .topTrailing) {
                // X button in upper right corner
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(.background.opacity(0.8), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(14)
            }
        }
        .matchedGeometryEffect(id: isInSidebar ? "sidebar-\(cityWeather.id)" : "marker-\(cityWeather.id)", in: namespace, isSource: true)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 0.8).combined(with: .opacity)
        ))
    }
    
    private var forecastDateText: String {
        let calendar = Calendar.current
        let today = Date()
        
        if let date = calendar.date(byAdding: .day, value: internalSelectedDay, to: today) {
            if internalSelectedDay == 0 {
                return "Today"
            } else if internalSelectedDay == 1 {
                return "Tomorrow"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE, MMMM d"
                return formatter.string(from: date)
            }
        }
        return ""
    }
}

struct TimelineForecastColumn: View {
    let hourlyForecast: HourlyForecast
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 7) {
            // Time
            Text(hourlyForecast.shortFormattedHour)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Weather icon
            Group {
                if hourlyForecast.isRainIcon {
                    let colors = hourlyForecast.rainPaletteColors(for: colorScheme)
                    Image(systemName: hourlyForecast.weatherIcon)
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(colors.primary, colors.secondary)
                } else if hourlyForecast.isPartiallySunnyIcon {
                    let colors = hourlyForecast.partlySunnyPaletteColors(for: colorScheme)
                    Image(systemName: hourlyForecast.weatherIcon)
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(colors.primary, colors.secondary)
                } else if hourlyForecast.isPartlyMoonIcon {
                    let colors = hourlyForecast.partlyMoonPaletteColors(for: colorScheme)
                    Image(systemName: hourlyForecast.weatherIcon)
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(colors.primary, colors.secondary)
                } else {
                    Image(systemName: hourlyForecast.weatherIcon)
                        .font(.title3)
                        .foregroundStyle(hourlyForecast.weatherColor(for: colorScheme))
                }
            }
            .frame(height: 28)
            
            // Temperature
            Text("\(Int(hourlyForecast.temperature))°")
                .font(.callout)
                .fontWeight(.semibold)
        }
        .frame(minWidth: 46)
    }
}

struct DayForecastBox: View {
    let dailyForecast: DailyForecast
    let isSelected: Bool
    let cornerRadius: RectangleCornerRadii
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(dailyForecast: DailyForecast, isSelected: Bool, cornerRadius: RectangleCornerRadii = .init()) {
        self.dailyForecast = dailyForecast
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
    }
    
    private var dayOfWeek: String {
        let calendar = Calendar.current
        let today = Date()
        
        if let date = calendar.date(byAdding: .day, value: dailyForecast.dayOffset, to: today) {
            if dailyForecast.dayOffset == 0 {
                return "Today"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEE"
                return formatter.string(from: date)
            }
        }
        return ""
    }
    
    var body: some View {
        VStack(spacing: 9) {
            // Weather icon
            Group {
                if dailyForecast.isRainIcon {
                    let colors = dailyForecast.rainPaletteColors(for: colorScheme)
                    Image(systemName: dailyForecast.weatherIcon)
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(colors.primary, colors.secondary)
                } else if dailyForecast.isPartiallySunnyIcon {
                    let colors = dailyForecast.partlySunnyPaletteColors(for: colorScheme)
                    Image(systemName: dailyForecast.weatherIcon)
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(colors.primary, colors.secondary)
                } else {
                    Image(systemName: dailyForecast.weatherIcon)
                        .font(.title2)
                        .foregroundStyle(dailyForecast.weatherColor(for: colorScheme))
                }
            }
            .frame(height: 30)
            
            // Day of week
            Text(dayOfWeek)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .medium)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(minWidth: 50)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05), in: UnevenRoundedRectangle(cornerRadii: cornerRadius))
        .overlay {
            UnevenRoundedRectangle(cornerRadii: cornerRadius)
                .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: isSelected ? 1.5 : 0.5)
        }
    }
}
#Preview("Weather Detail - London", traits: .portrait) {
    @Previewable @Namespace var namespace
    @Previewable @State var showDetail = true
    
    let london = City(name: "London", latitude: 51.5074, longitude: -0.1278)
    
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
            precipitationChance: precipChance
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
                precipitationChance: precipChance
            )
        }
        
        return DailyForecast(
            dayOffset: dayOffset,
            temperature: baseTemp,
            symbolName: symbol,
            condition: condition,
            hourlyForecasts: dayOffset == 0 ? hourlyForecasts : dayHourlyForecasts
        )
    }
    
    let londonWeather = CityWeather(
        city: london,
        condition: .partlyCloudy,
        temperature: 15,
        symbolName: "cloud.sun",
        dailyForecasts: dailyForecasts
    )
    
    ZStack {
        // Background
        LinearGradient(
            colors: [.blue.opacity(0.6), .cyan.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        if showDetail {
            WeatherDetailView(
                cityWeather: londonWeather,
                selectedDayOffset: 0,
                namespace: namespace,
                onDismiss: { },
                onAddCity: {
                    print("Add London to sidebar")
                },
                isInSidebar: false
            )
        }
    }
}

