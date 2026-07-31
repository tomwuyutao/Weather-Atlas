//
//  WeatherService.swift
//  Weather
//
//  Purpose: Fetches WeatherKit data, resolves place metadata, and converts
//  WeatherKit responses into app weather models.
//

import CoreLocation
import Foundation
import WeatherKit

// MARK: - Service Errors

/// Service failures that must surface instead of producing fabricated weather.
enum WeatherServiceError: LocalizedError {
    case undefinedTimeZone(city: String)
    case unresolvedPlace(city: String)

    /// Diagnostic description forwarded to the native warning pipeline.
    var errorDescription: String? {
        switch self {
        case .undefinedTimeZone(let city):
            return "Timezone undefined for \(city)"
        case .unresolvedPlace(let city):
            return "Place unresolved for \(city)"
        }
    }
}

/// Thin WeatherKit adapter shared by the place-keyed forecast repository.
@MainActor
final class WeatherService {
    // MARK: Resolution State

    /// In-process timezone cache keyed by rounded coordinates.
    var resolvedTimeZones: [String: TimeZone] = [:]
    /// In-process place cache keyed by rounded coordinates.
    var resolvedPlaces: [String: ResolvedPlace] = [:]
    
    // MARK: WeatherKit

    /// Shared Apple WeatherKit client.
    let weatherKitService = WeatherKit.WeatherService.shared

    // MARK: Error Reporting

    /// Logs a service error. PlaceWeatherStore owns user-facing failures.
    func report(_ error: Error) {
        #if DEBUG
        print("[WeatherService] \(error.localizedDescription)")
        #endif
    }

    /// Records an internal invariant or persistence diagnostic in debug builds.
    func reportDeveloperWarning(title: String, message: String) {
        DeveloperDiagnostics.show(title: title, message: message)
    }

    // MARK: WeatherKit Conversion

    /// Resolves timezone before converting WeatherKit data for a city.
    func convertWeatherKitData(weather: Weather, for city: City) async throws -> CityWeather {
        let timeZone = try await resolvedTimeZoneOrThrow(for: city)
        return convertWeatherKitData(weather: weather, for: city, timeZone: timeZone)
    }
    
    /// Converts WeatherKit source values without filling omitted optional fields.
    func convertWeatherKitData(weather: Weather, for city: City, timeZone: TimeZone) -> CityWeather {
        let currentTemp = weather.currentWeather.temperature.value

        let dailyForecasts = weather.dailyForecast.forecast.enumerated().map { (index, day) -> DailyForecast in
            let daySymbol = day.symbolName
            let daytimeForecast = day.daytimeForecast
            let hourlyForecasts = generateHourlyFromDaily(
                day: day,
                allHourly: weather.hourlyForecast.forecast,
                timeZone: timeZone
            )

            return DailyForecast(
                date: day.date,
                dayOffset: index,
                dailyLow: day.lowTemperature.value,
                dailyHigh: day.highTemperature.value,
                symbolName: daySymbol,
                condition: AppWeatherCondition.fromWeatherKit(
                    day.condition,
                    isDaylight: true
                ) ?? AppWeatherCondition.fromWeatherSymbol(daySymbol),
                hourlyForecasts: hourlyForecasts,
                cloudCover: daytimeForecast.cloudCover,
                precipitationChance: daytimeForecast.precipitationChance,
                uvIndex: day.uvIndex.value,
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset
            )
        }

        let currentWeather = weather.currentWeather
        return CityWeather(
            city: city,
            temperature: currentTemp,
            currentSymbolName: currentWeather.symbolName,
            currentCondition: AppWeatherCondition.fromWeatherKit(
                currentWeather.condition,
                isDaylight: currentWeather.isDaylight
            ) ?? AppWeatherCondition.fromWeatherSymbol(currentWeather.symbolName),
            dailyForecasts: Array(dailyForecasts),
            timeZone: timeZone
        )
    }
    
    /// Selects hourly records whose absolute instants fall in one city-local day.
    private func generateHourlyFromDaily(day: DayWeather, allHourly: [HourWeather], timeZone: TimeZone) -> [HourlyForecast] {
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let dayStart = calendar.startOfDay(for: day.date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        let dayHourlyData = allHourly.filter { hourWeather in
            hourWeather.date >= dayStart && hourWeather.date < dayEnd
        }
        
        if dayHourlyData.isEmpty { return [] }
        
        return dayHourlyData.map { hourWeather in
            HourlyForecast(
                date: hourWeather.date,
                symbolName: hourWeather.symbolName,
                condition: AppWeatherCondition.fromWeatherKit(
                    hourWeather.condition,
                    isDaylight: hourWeather.isDaylight
                ) ?? AppWeatherCondition.fromWeatherSymbol(hourWeather.symbolName),
                temperature: hourWeather.temperature.value,
                apparentTemperature: hourWeather.apparentTemperature.value,
                cloudCover: hourWeather.cloudCover,
                precipitationChance: hourWeather.precipitationChance,
                uvIndex: hourWeather.uvIndex.value,
                visibilityKilometers: hourWeather.visibility.converted(to: .kilometers).value
            )
        }
    }
    // MARK: Per-City Fetching

    /// Retries one failed WeatherKit network request before allowing its error
    /// to reach the user-facing warning pipeline. This covers work interrupted
    /// while the app is suspended and ordinary transient connection timeouts.
    private func weatherWithOneRetry(for location: CLLocation) async throws -> Weather {
        do {
            return try await weatherKitService.weather(for: location)
        } catch {
            // Do not turn an intentional task cancellation into a second request.
            try Task.checkCancellation()
            // Give a newly foregrounded app and its network path a brief moment
            // to recover before retrying the exact same WeatherKit request.
            try? await Task.sleep(for: .milliseconds(400))
            try Task.checkCancellation()
            return try await weatherKitService.weather(for: location)
        }
    }

    /// Resolves and fetches one city, reporting failure and returning `nil`.
    func fetchWeatherForCity(_ city: City) async -> CityWeather? {
        do {
            // Fetch weather for the city
            let resolvedCity = try await resolvedCity(for: city)
            let location = CLLocation(latitude: resolvedCity.latitude, longitude: resolvedCity.longitude)
            let weather = try await weatherWithOneRetry(for: location)
            
            // Convert to our model
            let cityWeather = try await convertWeatherKitData(weather: weather, for: resolvedCity)
            
            return cityWeather
        } catch {
            report(error)
            return nil
        }
    }

}
