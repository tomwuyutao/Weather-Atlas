//
//  MapMarkerView.swift
//  Weather
//
//  Weather marker and selected pulse rendering.
//

import SwiftUI

enum MarkerDisplayMode {
    case card
    case dot
}

struct SelectedPulseRing: View {
    enum Shape { case circle, roundedRect }
    let shape: Shape
    var color: Color = .white
    @State private var isPulsing = false

    var body: some View {
        Group {
            switch shape {
            case .circle:
                Circle()
                    .stroke(color.opacity(isPulsing ? 0.3 : 0.8), lineWidth: isPulsing ? 1.5 : 2.5)
                    .frame(width: 30, height: 30)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
            case .roundedRect:
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(isPulsing ? 0.4 : 0.9), lineWidth: isPulsing ? 2.5 : 3)
            }
        }
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
    }
}

struct WeatherMarker: View {
    let cityWeather: CityWeather
    let dayOffset: Int
    let isCompact: Bool
    let namespace: Namespace.ID
    let showCloudCover: Bool
    var overlayMode: String = "weather"
    var filterSunny: Bool = false
    var passesFilter: Bool = true
    var displayMode: MarkerDisplayMode = .card
    var isSelected: Bool = false
    var hideCityName: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    
    var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    var distUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    var isNow: Bool { dayOffset == -1 }

    var forecast: DailyForecast {
        cityWeather.forecast(for: max(0, dayOffset))
    }

    var showAsDot: Bool { displayMode == .dot }
    var showAsCard: Bool { displayMode == .card }

    /// Whether the data required by the current overlay mode is available.
    /// When false the entire marker should be hidden.
    var hasOverlayData: Bool {
        if isNow {
            switch overlayMode {
            case "cloudCover":    return cityWeather.currentCloudCover != nil
            case "precipitation": return true // derived from condition
            case "windSpeed":     return cityWeather.currentWindSpeed != nil
            case "uvIndex":       return cityWeather.currentUVIndex != nil
            case "humidity":      return cityWeather.currentHumidity != nil
            case "visibility":    return cityWeather.currentVisibility != nil
            default:              return true
            }
        }
        switch overlayMode {
        case "cloudCover":    return forecast.cloudCover != nil
        case "precipitation": return forecast.precipitationChance != nil
        case "windSpeed":     return forecast.windSpeed != nil
        case "uvIndex":       return forecast.uvIndex != nil
        case "humidity":      return forecast.maxHumidity != nil
        case "visibility":    return forecast.maxVisibility != nil
        default:              return true // "weather" / "temperature" always available
        }
    }

    var overlayPinText: String {
        switch overlayMode {
        case "cloudCover":
            if isNow {
                guard let cc = cityWeather.currentCloudCover else { return "—" }
                return "\(Int(cc * 100))%"
            }
            guard let cc = forecast.cloudCoverPercent else { return "—" }
            return "\(cc)%"
        case "precipitation":
            if isNow {
                let isRaining = [.rain, .drizzle, .snow].contains(cityWeather.condition)
                return isRaining ? "100%" : "0%"
            }
            guard let pc = forecast.precipitationChance else { return "—" }
            return "\(Int(pc * 100))%"
        case "windSpeed":
            if isNow {
                guard let ws = cityWeather.currentWindSpeed else { return "—" }
                return distUnit.displayWindSpeed(ws)
            }
            guard let ws = forecast.windSpeed else { return "—" }
            return distUnit.displayWindSpeed(ws)
        case "uvIndex":
            if isNow {
                guard let uv = cityWeather.currentUVIndex else { return "—" }
                return "\(uv)"
            }
            guard let uv = forecast.uvIndex else { return "—" }
            return "\(uv)"
        case "humidity":
            if isNow {
                guard let hum = cityWeather.currentHumidity else { return "—" }
                return "\(Int(hum * 100))%"
            }
            guard let hum = forecast.maxHumidity else { return "—" }
            return "\(Int(hum * 100))%"
        case "visibility":
            if isNow {
                guard let km = cityWeather.currentVisibility else { return "—" }
                return km >= 10 ? "\(Int(km))" : String(format: "%.1f", km)
            }
            guard let km = forecast.maxVisibility else { return "—" }
            return km >= 10 ? "\(Int(km))" : String(format: "%.1f", km)
        default:
            return tempUnit.display(isNow ? cityWeather.temperature : forecast.dailyHigh)
        }
    }

    var dotColor: Color {
        // Temperature overlay: use current temp for "Now", daily high otherwise
        let tempForColor = isNow ? cityWeather.temperature : forecast.dailyHigh
        if overlayMode == "temperature" {
            let tempC = tempForColor
            if tempC <= 0 {
                return Color(hex: 0xD3E3EC).mix(with: Color(hex: 0x6EACE8), by: max(0, min(1, (tempC + 20) / 20)))
            } else if tempC <= 10 {
                return Color(hex: 0x6EACE8).mix(with: Color(hex: 0xEEB368), by: max(0, min(1, tempC / 10)))
            } else if tempC <= 20 {
                return Color(hex: 0xEEB368).mix(with: Color(hex: 0xFF8A65), by: max(0, min(1, (tempC - 10) / 10)))
            } else {
                return Color(hex: 0xFF8A65).mix(with: Color(hex: 0xFB4368), by: max(0, min(1, (tempC - 20) / 20)))
            }
        }
        if overlayMode == "cloudCover" {
            let cloudCoverVal: Double? = isNow ? cityWeather.currentCloudCover : forecast.cloudCover
            guard let cloudCoverVal else { return .gray }
            return Color.white.mix(with: Color(hex: 0xD3E3EC), by: max(0, min(1, cloudCoverVal)))
        }
        if overlayMode == "precipitation" {
            let chance: CGFloat
            if isNow {
                chance = [.rain, .drizzle, .snow].contains(cityWeather.condition) ? 1.0 : 0.0
            } else {
                guard let precipVal = forecast.precipitationChance else { return .gray }
                chance = CGFloat(precipVal)
            }
            return Color.white.mix(with: Color(hex: 0xBCCFDC), by: Double(chance))
        }
        if overlayMode == "windSpeed" {
            let ws: Double? = isNow ? cityWeather.currentWindSpeed : forecast.windSpeed
            guard let ws else { return .gray }
            return Color.white.mix(with: Color(hex: 0xEEB368), by: min(1.0, ws / 100.0))
        }
        // UV index overlay: white (0) → red #FB4368 (11+)
        if overlayMode == "uvIndex" {
            let uvVal: Int? = isNow ? cityWeather.currentUVIndex : forecast.uvIndex
            guard let uvVal else { return .gray }
            let uv = min(1.0, Double(uvVal) / 11.0)
            return Color(
                red: 1.0 + uv * (Double(0xE8) / 255.0 - 1.0),
                green: 1.0 + uv * (Double(0x79) / 255.0 - 1.0),
                blue: 1.0 + uv * (Double(0x57) / 255.0 - 1.0)
            )
        }
        if overlayMode == "humidity" {
            let hum: Double? = isNow ? cityWeather.currentHumidity : forecast.maxHumidity
            guard let hum else { return .gray }
            return Color(
                red: 1.0 + hum * (Double(0xBC) / 255.0 - 1.0),
                green: 1.0 + hum * (Double(0xCF) / 255.0 - 1.0),
                blue: 1.0 + hum * (Double(0xDC) / 255.0 - 1.0)
            )
        }
        if overlayMode == "visibility" {
            let visVal: Double? = isNow ? cityWeather.currentVisibility : forecast.maxVisibility
            guard let visVal else { return .gray }
            return Color.white.mix(with: Color(hex: 0xBCCFDC), by: min(1.0, visVal / 30.0))
        }
        if baseIcon.contains("moon") {
            return AppTheme.shared.colors.moonIconColor
        }
        // Default weather dot color
        return displayCondition.dotColor
    }

    var baseCondition: AppWeatherCondition {
        isNow ? cityWeather.condition : forecast.condition
    }

    var baseIcon: String {
        isNow ? cityWeather.weatherIcon : forecast.weatherIcon
    }

    var displayIcon: String {
        if filterSunny {
            return passesFilter ? "sun.max.fill" : baseIcon
        }
        // Use plain cloud for rain/drizzle/snow — the animation shows the precipitation
        if baseCondition == .rain || baseCondition == .drizzle || baseCondition == .snow {
            return "cloud.fill"
        }
        return baseIcon
    }

    var displayCondition: AppWeatherCondition {
        if filterSunny && passesFilter {
            return .clear
        }
        // Match animation to the displayed icon, not raw condition
        let icon = displayIcon
        if icon == "cloud.fill" {
            switch baseCondition {
            case .rain: return .rain
            case .drizzle: return .drizzle
            case .snow: return .snow
            default: return .cloudy
            }
        }
        return baseCondition
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Pulse ring behind everything
            if isSelected {
                SelectedPulseRing(shape: .circle, color: dotColor)
                    .frame(width: 10, height: 10)
            }

            // Dot layer — always present as anchor
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .shadow(color: dotColor.opacity(isSelected ? 0.8 : 0.5), radius: isSelected ? 12 : 4)
                .scaleEffect(isSelected ? 1.5 : 1.0)

            // Pin label layer — floats above the dot
            if showAsCard {
                pinView
                    .fixedSize()
                    .transition(.scale(scale: 0.01, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 10, height: 10, alignment: .bottom)
        .contentShape(Rectangle())
        .opacity(hasOverlayData ? 1 : 0)
        .allowsHitTesting(hasOverlayData)
        .animation(.easeInOut(duration: 0.3), value: displayMode)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.smooth(duration: 0.4), value: dayOffset)
    }

    var pinView: some View {
        VStack(spacing: 1) {
            // Temperature — primary, largest
            Text(overlayPinText)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(AppTheme.shared.colors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.4), value: dayOffset)
                .offset(x: 2)
                .animation(.smooth(duration: 0.4), value: overlayMode)

            // City name — secondary, smaller (hidden when detail card is shown)
            if !hideCityName {
                Text(cityWeather.city.localizedName(locale: locale))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.shared.colors.primaryText.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .offset(y: -16)
    }
}
