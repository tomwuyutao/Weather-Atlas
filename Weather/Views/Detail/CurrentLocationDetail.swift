//
//  CurrentLocationDetail.swift
//  Weather
//
//  Purpose: Presents the full current-location forecast without treating it
//  as a saved place or exposing Saved Places actions.
//

import SwiftUI

struct CurrentLocationDetailView: View {
    @Bindable var model: WeatherAtlasModel
    @Binding private var selectedDate: Date

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    init(model: WeatherAtlasModel, selectedDate: Binding<Date>) {
        self.model = model
        _selectedDate = selectedDate
    }

    private var weather: CityWeather? { model.currentLocationWeather }

    private var forecast: DailyForecast? {
        weather?.forecastIfAvailable(
            on: selectedDate,
            selectionCalendar: calendar
        )
    }

    private var locationName: String {
        guard let resolvedName = model.locationProvider.metadata?.displayName
            ?? weather?.city.displayName,
              !resolvedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return localizedString("Current Location", locale: locale)
        }
        return resolvedName
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    var body: some View {
        Group {
            if let weather {
                report(for: weather)
            } else {
                ContentUnavailableView(
                    "Current Location Unavailable",
                    systemImage: "location.slash",
                    description: Text(
                        "Return Home to enable location and load a local forecast."
                    )
                )
            }
        }
        .weatherAtlasScreenBackground()
        .navigationTitle(locationName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TopForecastDateSwitcher(
                    selection: $selectedDate,
                    availableDates: ForecastDateHorizon.dates(in: model.forecastCalendar)
                )
            }
        }
        .refreshable {
            guard model.locationProvider.hasUsableCoordinate else { return }
            await model.refreshHomeWeather(forceRefresh: true, locale: locale)
        }
    }

    private func report(for weather: CityWeather) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                CurrentLocationDetailHeader(
                    locationName: locationName,
                    forecast: forecast
                )

                if let forecast {
                    DetailMetricGrid(
                        city: weather,
                        forecast: forecast,
                        temperatureUnit: temperatureUnit,
                        usesLandscapeIPadLayout: false,
                        selectedForecastDate: $selectedDate
                    )

                    // Home uses this exact component too, so both screens
                    // render the same ten-day sunny-hours chart and semantics.
                    SunnyHoursOverviewCard(
                        city: weather,
                        selectedDate: $selectedDate
                    )
                } else {
                    ContentUnavailableView(
                        "No Forecast for This Date",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Choose another available date.")
                    )
                    .padding(WeatherCardLayout.padding)
                    .detailTranslucentCard(
                        colorScheme: colorScheme,
                        in: RoundedRectangle(
                            cornerRadius: WeatherCardLayout.cornerRadius,
                            style: .continuous
                        )
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.background)
    }
}

private struct CurrentLocationDetailHeader: View {
    let locationName: String
    let forecast: DailyForecast?

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 9) {
            Text(locationName)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)

            if let forecast {
                let condition = SunninessScoring.condition(for: forecast)
                let icon = condition?.displayIcon ?? forecast.symbolName

                Image(systemName: icon)
                    .weatherIconStyle(for: icon)
                    .font(.system(size: 52, weight: .semibold))
                    .frame(width: 62, height: 58)
                    .padding(.vertical, 8)

                Text(
                    condition?.localizedDisplayName(locale: locale)
                        ?? localizedString("Forecast", locale: locale)
                )
                .font(.callout)
                .foregroundStyle(theme.colors.primaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }
}
