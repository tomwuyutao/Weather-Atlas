//
//  WidgetCatalogPublisher.swift
//  Weather
//
//  Purpose: Converts the app's saved lists and WeatherKit-backed forecasts into
//  the shared widget catalog and per-city widget cache.
//

import Foundation

// MARK: - Sunny-Hour Breakdown

private struct WidgetSunnyHourBreakdown {
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
    let daylightBounds: SunnyHoursChartBounds?
    let dataIssue: WeatherDataIssue?

    init(data: SunninessScoring.SunnyHoursData, timeZone: TimeZone) {
        var daytimeHours: [Int] = []
        var sunnyHours: [Int] = []
        var partlySunnyHours: [Int] = []
        var symbolIssue: WeatherDataIssue?

        for forecast in data.hours {
            let hour = forecast.hour(in: timeZone)
            daytimeHours.append(hour)

            switch SunninessScoring.condition(for: forecast.symbolName) {
            case .clear:
                sunnyHours.append(hour)
            case .partlySunny:
                partlySunnyHours.append(hour)
            case .partlyCloudy, .cloudy, .rain, .drizzle, .snow, .fog, .wind:
                break
            case nil:
                symbolIssue = .unknownWeatherSymbol(forecast.symbolName)
            }
        }

        if let symbolIssue {
            self.daytimeHours = []
            self.sunnyHours = []
            self.partlySunnyHours = []
            self.daylightBounds = nil
            self.dataIssue = symbolIssue
        } else {
            self.daytimeHours = daytimeHours
            self.sunnyHours = sunnyHours
            self.partlySunnyHours = partlySunnyHours
            self.daylightBounds = data.bounds
            self.dataIssue = nil
        }
    }

    init(issue: WeatherDataIssue) {
        daytimeHours = []
        sunnyHours = []
        partlySunnyHours = []
        daylightBounds = nil
        dataIssue = issue
    }
}

// MARK: - Catalog Publication

extension ContentView {
    func publishWidgetCatalog() {
        guard !isListPreviewActive else { return }
        WidgetDataStore.save(
            WidgetDataCatalog(
                lists: managedLists.map(widgetDataList),
                appLanguageIdentifier: locale.identifier
            )
        )
    }

    private func widgetDataList(for listID: CityListID) -> WidgetDataList {
        let weatherData = weatherService.weatherData(for: listID)
        let cities = weatherService.cityListCoordinates(for: listID).map { sourceCity in
            widgetDataCity(for: sourceCity, weatherData: weatherData, listID: listID)
        }
        return WidgetDataList(
            id: listID.rawValue,
            displayName: listID.localizedDisplayName(locale: locale),
            cities: cities
        )
    }

    private func widgetDataCity(
        for sourceCity: City,
        weatherData: [CityWeather],
        listID: CityListID
    ) -> WidgetDataCity {
        let cityWeather = weatherData.first { weatherService.citiesMatch($0.city, sourceCity) }
        let displayCity = cityWeather?.city ?? sourceCity
        let cityID = WidgetDataStore.cityIdentifier(
            country: displayCity.country,
            latitude: displayCity.latitude,
            longitude: displayCity.longitude,
            listID: listID.rawValue
        )
        let currentForecast = cityWeather?.forecastForLocalDate(containing: Date())
        let currentHours: WidgetSunnyHourBreakdown?
        if let cityWeather, let currentForecast {
            currentHours = widgetSunnyHours(for: currentForecast, cityWeather: cityWeather)
        } else {
            currentHours = nil
        }
        let timeZoneIdentifier = cityWeather?.timeZone.identifier ?? displayCity.timeZoneIdentifier
        let dataIssue: WeatherDataIssue? = {
            guard timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil else {
                return .missingTimeZone
            }
            guard cityWeather != nil, currentForecast != nil else {
                return .missingForecastData
            }
            return currentHours?.dataIssue
        }()
        let widgetCity = WidgetDataCity(
            id: cityID,
            cityName: localizedCityDisplayName(for: displayCity, locale: locale),
            timeZoneIdentifier: timeZoneIdentifier,
            latitude: displayCity.latitude,
            longitude: displayCity.longitude,
            daytimeHours: currentHours?.daytimeHours ?? [],
            sunnyHours: currentHours?.sunnyHours ?? [],
            partlySunnyHours: currentHours?.partlySunnyHours ?? [],
            currentConditionSymbolName: cityWeather?.currentSymbolName,
            daylightBounds: currentHours?.daylightBounds,
            sunnyWindowDays: cityWeather.map(widgetSunnyWindowDays) ?? [],
            dataIssue: dataIssue
        )

        if currentForecast != nil,
           let fetchedAt = weatherService.fetchDate(for: listID) {
            WidgetDataStore.saveWeatherSnapshot(
                WidgetWeatherSnapshot(fetchedAt: fetchedAt, city: widgetCity),
                for: cityID
            )
        }
        return widgetCity
    }

    private func widgetSunnyWindowDays(for cityWeather: CityWeather) -> [WidgetSunnyWindowDay] {
        cityWeather.dailyForecasts.compactMap { forecast in
            guard let selectionDate = cityWeather.selectionDate(for: forecast) else { return nil }
            let hours = widgetSunnyHours(for: forecast, cityWeather: cityWeather)
            return WidgetSunnyWindowDay(
                date: selectionDate,
                sunnyHours: hours.sunnyHours,
                partlySunnyHours: hours.partlySunnyHours,
                daylightBounds: hours.daylightBounds,
                dataIssue: hours.dataIssue
            )
        }
    }

    private func widgetSunnyHours(
        for forecast: DailyForecast,
        cityWeather: CityWeather
    ) -> WidgetSunnyHourBreakdown {
        switch SunninessScoring.sunnyHoursData(for: forecast, timeZone: cityWeather.timeZone) {
        case .success(let data):
            return WidgetSunnyHourBreakdown(data: data, timeZone: cityWeather.timeZone)
        case .failure(let issue):
            return WidgetSunnyHourBreakdown(issue: issue)
        }
    }
}
