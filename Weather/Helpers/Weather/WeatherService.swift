//
//  WeatherService.swift
//  Weather
//
//  Purpose: Fetches WeatherKit data, resolves place metadata, and converts
//  WeatherKit responses into app weather models. This is the narrow adapter
//  between Apple's SDK types and the app's Codable, view-friendly models.
//

import CoreLocation
import Foundation
import WeatherKit

// MARK: - Service Errors

/// Service failures that must surface instead of producing fabricated weather.
enum WeatherServiceError: LocalizedError {
    case requestFailed(city: String, detail: String)
    case undefinedTimeZone(city: String)
    case unresolvedPlace(city: String)
    case missingForecastData(city: String)
    case invalidWeatherData(city: String, issue: WeatherDataIssue)

    /// Diagnostic description forwarded to the native warning pipeline.
    var errorDescription: String? {
        switch self {
        case .requestFailed(let city, let detail):
            return "Weather request failed for \(city): \(detail)"
        case .undefinedTimeZone(let city):
            return "Timezone undefined for \(city)"
        case .unresolvedPlace(let city):
            return "Place unresolved for \(city)"
        case .missingForecastData(let city):
            return "Forecast data missing for \(city)"
        case .invalidWeatherData(let city, let issue):
            return "Invalid weather data for \(city): \(issue.detail ?? "unknown numeric value")"
        }
    }

    /// Structured data issue retained by the repository and native-alert layer.
    var dataIssue: WeatherDataIssue {
        switch self {
        case .requestFailed(_, let detail):
            return .weatherRequestFailed(detail)
        case .undefinedTimeZone:
            return .missingTimeZone
        case .unresolvedPlace(let city):
            return .unresolvedPlace(city)
        case .missingForecastData:
            return .missingForecastData
        case .invalidWeatherData(_, let issue):
            return issue
        }
    }
}

/// Successful WeatherKit conversion. Response-wide structure is evaluated later
/// by ForecastValidation; hourly consumers validate only the records they use.
struct WeatherServiceResponse {
    let weather: CityWeather
}

/// Thin WeatherKit adapter shared by the place-keyed forecast repository.
///
/// The whole service is `@MainActor` because its short-lived resolution caches
/// are UI-owned mutable state. WeatherKit's async work still suspends rather
/// than blocking the main thread while the request is in flight.
@MainActor
final class WeatherService {
    // MARK: Resolution State

    /// In-process timezone cache keyed by exact coordinate bit patterns.
    /// These are performance caches only: they are not persisted and may be
    /// rebuilt after every launch without changing the app's correctness.
    var resolvedTimeZones: [String: TimeZone] = [:]
    /// In-process place cache keyed by exact coordinates plus app locale.
    var resolvedPlaces: [String: ResolvedPlace] = [:]
    
    // MARK: WeatherKit

    /// Shared Apple WeatherKit client.
    let weatherKitService = WeatherKit.WeatherService.shared

    // MARK: Error Reporting

    /// Records an internal invariant or persistence diagnostic in debug builds.
    func reportDeveloperWarning(title: String, message: String) {
        DeveloperDiagnostics.show(title: title, message: message)
    }

    // MARK: WeatherKit Conversion

    /// Resolves timezone before converting WeatherKit data for a city.
    func convertWeatherKitData(
        weather: Weather,
        for city: City
    ) async throws -> WeatherServiceResponse {
        let timeZone = try await resolvedTimeZoneOrThrow(for: city)
        return try convertWeatherKitData(
            weather: weather,
            for: city,
            timeZone: timeZone
        )
    }
    
    /// Converts WeatherKit source values without filling omitted optional fields.
    ///
    /// WeatherKit uses `Measurement` values and its own condition enums. This
    /// method extracts numeric values in the app's canonical units and keeps
    /// missing source fields as optionals, so downstream UI never confuses an
    /// absence of data with a real zero.
    func convertWeatherKitData(
        weather: Weather,
        for city: City,
        timeZone: TimeZone
    ) throws -> WeatherServiceResponse {
        let dailyForecasts = weather.dailyForecast.forecast.map { day -> DailyForecast in
            // WeatherKit returns one continuous hourly series. Re-slice it for
            // each daily model so each Detail timeline owns exactly one local day.
            let daySymbol = day.symbolName
            let daytimeForecast = day.daytimeForecast
            let hourlyForecasts = generateHourlyFromDaily(
                day: day,
                allHourly: weather.hourlyForecast.forecast,
                timeZone: timeZone
            )

            return DailyForecast(
                date: day.date,
                dailyLow: day.lowTemperature.value,
                dailyHigh: day.highTemperature.value,
                symbolName: daySymbol,
                condition: resolvedCondition(
                    day.condition,
                    isDaylight: true,
                    symbolName: daySymbol
                ),
                isFullyClear: day.condition == .clear,
                hourlyForecasts: hourlyForecasts,
                cloudCover: daytimeForecast.cloudCover,
                precipitationChance: daytimeForecast.precipitationChance,
                uvIndex: day.uvIndex.value,
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset
            )
        }

        guard !dailyForecasts.isEmpty else {
            throw WeatherServiceError.missingForecastData(
                city: city.displayName
            )
        }

        let cityWeather = CityWeather(
            city: city,
            dailyForecasts: Array(dailyForecasts),
            timeZone: timeZone
        )
        // WeatherKit values are strongly typed but still cross a provider
        // boundary. Reject non-finite, out-of-domain, or internally inconsistent
        // numeric readings before any view can clamp or format them as plausible.
        if let issue = cityWeather.numericDataIssues.first {
            throw WeatherServiceError.invalidWeatherData(
                city: city.displayName,
                issue: issue
            )
        }
        return WeatherServiceResponse(weather: cityWeather)
    }

    /// Resolves WeatherKit's semantic enum first, then its separately supplied
    /// raw symbol only when that symbol has an explicit known classification.
    /// Both are real WeatherKit fields; an unrecognized value remains nil.
    private func resolvedCondition(
        _ condition: WeatherKit.WeatherCondition,
        isDaylight: Bool,
        symbolName: String
    ) -> AppWeatherCondition? {
        if let semanticCondition = AppWeatherCondition.fromWeatherKit(
            condition,
            isDaylight: isDaylight
        ) {
            return semanticCondition
        }
        return AppWeatherCondition.fromWeatherSymbol(symbolName)
    }

    /// Selects hourly records whose absolute instants fall in one city-local day.
    ///
    /// Dates are absolute instants, while "today" is a civil-calendar concept.
    /// Setting the calendar's timezone before calculating midnight prevents a
    /// city near the user's timezone boundary from receiving the wrong hours.
    private func generateHourlyFromDaily(day: DayWeather, allHourly: [HourWeather], timeZone: TimeZone) -> [HourlyForecast] {
        var calendar = Calendar.current
        calendar.timeZone = timeZone

        let dayStart = calendar.startOfDay(for: day.date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        // The half-open interval `[dayStart, dayEnd)` includes midnight once and
        // never assigns the first hour of tomorrow to both days.
        let dayHourlyData = allHourly.filter { hourWeather in
            hourWeather.date >= dayStart && hourWeather.date < dayEnd
        }
        
        if dayHourlyData.isEmpty { return [] }
        
        return dayHourlyData.map { hourWeather in
            // Classification is resolved exactly once at this adapter boundary.
            HourlyForecast(
                date: hourWeather.date,
                symbolName: hourWeather.symbolName,
                condition: resolvedCondition(
                    hourWeather.condition,
                    isDaylight: hourWeather.isDaylight,
                    symbolName: hourWeather.symbolName
                ),
                isDaylight: hourWeather.isDaylight,
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
            // Retry only errors that describe a temporary network path. WeatherKit
            // permission failures, malformed requests, and unknown permanent
            // service errors must reach the blank-state alert immediately.
            guard isTransientWeatherRequestError(error) else { throw error }
            // Give a newly foregrounded app and its network path a brief moment
            // to recover before retrying the exact same WeatherKit request.
            // This suspension does not block the main actor. Propagating its
            // cancellation error guarantees a cancelled request never retries.
            try await Task.sleep(for: .milliseconds(400))
            try Task.checkCancellation()
            return try await weatherKitService.weather(for: location)
        }
    }

    private func isTransientWeatherRequestError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    /// Resolves and fetches one city while preserving final typed failures.
    /// Query-budgeted callers can disable the normal single transient retry.
    func fetchWeatherForCity(
        _ city: City,
        retriesOnFailure: Bool = true
    ) async throws -> WeatherServiceResponse {
        do {
            // Resolve a display-only city into coordinates/name metadata before
            // requesting WeatherKit. WeatherKit itself ultimately uses location.
            let resolvedCity = try await resolvedCity(for: city)
            let location = CLLocation(latitude: resolvedCity.latitude, longitude: resolvedCity.longitude)
            let weather: Weather
            if retriesOnFailure {
                weather = try await weatherWithOneRetry(for: location)
            } else {
                weather = try await weatherKitService.weather(for: location)
            }
            
            // Convert Apple SDK objects at this boundary; views only see the
            // app's own stable models after this point.
            return try await convertWeatherKitData(
                weather: weather,
                for: resolvedCity
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let serviceError as WeatherServiceError {
            reportDeveloperWarning(
                title: "Weather Request Failed",
                message: serviceError.localizedDescription
            )
            throw serviceError
        } catch {
            let serviceError = WeatherServiceError.requestFailed(
                city: city.displayName,
                detail: error.localizedDescription
            )
            reportDeveloperWarning(
                title: "Weather Request Failed",
                message: serviceError.localizedDescription
            )
            throw serviceError
        }
    }

}
