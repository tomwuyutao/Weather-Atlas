//
//  FindSunListView.swift
//  Weather
//
//  Purpose: Presents queried sunny places in the Map navigation stack using
//  the same planning layout as Saved Places.
//

import SwiftUI

// MARK: - Find Sun Results Dashboard

/// A planning dashboard for the places returned by a Find Sun query. It
/// deliberately shares Saved Places' date and ranking cards so both surfaces
/// answer the same question with the same visual language.
struct FindSunListView: View {
    // MARK: - Inputs and Environment

    let results: [MapSunSearchResult]
    let title: String
    /// The full geographic pool remains available even when a city has no
    /// recommendation on the currently selected day. It drives date selection
    /// and planning summaries independently from the current ranking rows.
    let candidateCities: [City]
    let model: WeatherModel?
    let router: AppNavigation?
    let forecastCalendar: Calendar
    @Binding private var selectedDate: Date

    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale

    // MARK: - Initialization

    init(
        results: [MapSunSearchResult],
        title: String,
        candidateCities: [City],
        model: WeatherModel,
        router: AppNavigation,
        selectedDate: Binding<Date>
    ) {
        self.results = results
        self.title = title
        self.candidateCities = candidateCities
        self.model = model
        self.router = router
        forecastCalendar = model.forecastCalendar
        _selectedDate = selectedDate
    }

    #if DEBUG
    /// Keeps Xcode previews independent of WeatherKit and the saved-place
    /// store. The live Map destination always uses the model-backed initializer.
    init(
        results: [MapSunSearchResult],
        title: String
    ) {
        let previewCalendar = Calendar.current
        self.results = results
        self.title = title
        self.candidateCities = results.map(\.city)
        self.model = nil
        self.router = nil
        self.forecastCalendar = previewCalendar
        _selectedDate = .constant(Date())
    }
    #endif

    // MARK: - Derived Forecast Data

    /// The active query's weather pool, not just the currently sunny subset.
    private var candidateWeathers: [CityWeather] {
        guard let model else {
            return results.map(\.recommendation.cityWeather)
        }

        var seenIDs: Set<City.ID> = []
        return candidateCities.compactMap { city in
            guard seenIDs.insert(city.id).inserted else { return nil }
            return model.weatherStore.weather(for: city.id)
        }
    }

    /// Every literal selector day represented by currently cached query
    /// weather. Deriving this inside the destination keeps its date picker
    /// responsive if another candidate finishes loading after navigation.
    private var candidateForecastDates: [Date] {
        let dates = candidateWeathers.flatMap { weather in
            weather.dailyForecasts.map { forecast in
                weather.selectionDate(
                    for: forecast,
                    selectionCalendar: forecastCalendar
                ) ?? forecastCalendar.startOfDay(for: forecast.date)
            }
        }
        return Array(Set(dates)).sorted()
    }

    /// Preserve an out-of-band shared date without pretending it has candidate
    /// weather. `dateSummaries` below deliberately includes only real forecast
    /// days, so the ranked recommendations never imply data exists when it is
    /// absent.
    private var datePickerDates: [Date] {
        Array(
            Set(
                candidateForecastDates
                    + [forecastCalendar.startOfDay(for: selectedDate)]
            )
        )
        .sorted()
    }

    private var dateSummaries: [BestSunnyDateSummary] {
        candidateForecastDates.compactMap { date in
            let recommendations = candidateWeathers.compactMap {
                $0.recommendation(
                    on: date,
                    selectionCalendar: forecastCalendar
                )
            }

            return BestSunnyDateSummary(
                date: date,
                recommendations: recommendations,
                locale: locale
            ) { recommendation in
                recommendation.cityWeather.city.localizedDisplayName(
                    locale: locale
                )
            }
        }
    }

    private var orderedResults: [MapSunSearchResult] {
        let resultsByID = Dictionary(
            uniqueKeysWithValues: results.map { ($0.id, $0) }
        )
        return PlaceRecommendation.ranked(
            results.map(\.recommendation),
            locale: locale
        )
        .compactMap { resultsByID[$0.id] }
    }

    // MARK: - Presentation

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 20) {
                    if !dateSummaries.isEmpty {
                        // Keep the full forecast-date union visible even when
                        // the selected day has no positive sunny-hour
                        // rankings. A different forecast day may still have
                        // valid results.
                        BestSunnyDatesCard(
                            summaries: dateSummaries,
                            selectedDate: $selectedDate,
                            presentationState: .ready
                        )
                    }

                    if results.isEmpty {
                        ContentUnavailableView(
                            "No sunny places for this date.",
                            systemImage: "sun.max"
                        )
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        FindSunPlacesCard(
                            results: orderedResults,
                            showDetails: showDetails
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: contentWidth(for: geometry.size))
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background(theme.colors.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TopForecastDateSwitcher(
                    selection: $selectedDate,
                    availableDates: datePickerDates
                )
            }
        }
    }

    private func contentWidth(for size: CGSize) -> CGFloat {
        AppContentLayout.maximumWidth(
            for: size,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    // MARK: - Navigation

    private func showDetails(_ result: MapSunSearchResult) {
        guard let model, let router else { return }
        if let savedPlaceID = model.placesStore.savedPlaceID(matching: result.city) {
            router.mapPath.append(.place(id: savedPlaceID))
        } else {
            model.registerTransientCity(result.city)
            router.mapPath.append(.place(id: result.id))
        }
    }
}

// MARK: - Results Card

/// Queried places use the same translucent ranking card as Saved Places, but
/// retain their Map search identities and display names.
private struct FindSunPlacesCard: View {
    let results: [MapSunSearchResult]
    let showDetails: (MapSunSearchResult) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: WeatherCardLayout.contentSpacing) {
            WeatherCardHeader(
                icon: "mappin.and.ellipse",
                title: "Best Sunny Places"
            )

            VStack(spacing: 0) {
                ForEach(results) { result in
                    Button {
                        showDetails(result)
                    } label: {
                        SunnyPlaceRecommendationRow(
                            recommendation: result.recommendation,
                            displayName: result.city.displayName
                        )
                    }
                    .buttonStyle(.plain)

                    if result.id != results.last?.id {
                        Divider()
                            .background(theme.colors.secondaryText.opacity(0.16))
                            .padding(
                                .leading,
                                SavedPlacesRankingListLayout.contentLeadingInset
                            )
                    }
                }
            }
        }
        .padding(WeatherCardLayout.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailTranslucentCard(
            colorScheme: colorScheme,
            in: RoundedRectangle(
                cornerRadius: WeatherCardLayout.cornerRadius,
                style: .continuous
            )
        )
    }
}

#if DEBUG

// MARK: - Previews

#Preview("Find Sun List", traits: .fixedLayout(width: 390, height: 700)) {
    NavigationStack {
        FindSunListView(
            results: MapSunResultsPreviewData.results,
            title: "Italy"
        )
        .environment(\.appTheme, .shared)
    }
}

#Preview("Find Sun List Empty", traits: .fixedLayout(width: 390, height: 700)) {
    NavigationStack {
        FindSunListView(
            results: [],
            title: "United Kingdom"
        )
        .environment(\.appTheme, .shared)
    }
}

#endif
