//
//  ContentView+Search.swift
//  Weather
//
//  Extracted from ContentView.swift
//

import SwiftUI
import CoreLocation

extension ContentView {

    // MARK: - Native City Search

    var nativeCitySearchScreen: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: inlineSearchText.isEmpty ? "magnifyingglass" : "map")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(theme.colors.secondaryText.opacity(0.7))

            if !inlineSearchText.isEmpty {
                Text(localizedString("No results", locale: locale))
                    .font(.avenir(.title3, weight: .medium))
                    .foregroundStyle(theme.colors.primaryText)

                Text(localizedString("Try a different search term", locale: locale))
                    .font(.avenir(.body, weight: .regular))
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background.ignoresSafeArea())
    }

    @ViewBuilder
    func nativeCitySearch<Content: View>(
        _ content: Content,
        placement: SearchFieldPlacement = .automatic
    ) -> some View {
        if showingInlineSearch {
            content
                .searchable(
                    text: $inlineSearchText,
                    isPresented: $showingInlineSearch,
                    placement: placement,
                    prompt: Text(localizedString("Search for a city", locale: locale))
                )
                .searchSuggestions {
                    nativeCitySearchSuggestions
                }
                .onChange(of: inlineSearchText) { _, newValue in
                    inlineSearchManager.search(query: newValue)
                    inlineSearchSelectionIndex = 0
                }
                .onChange(of: showingInlineSearch) { _, isPresented in
                    if !isPresented {
                        resetNativeCitySearch()
                    }
                }
                .onSubmit(of: .search) {
                    confirmInlineSearchSelection()
                }
        } else {
            content
        }
    }

    @ViewBuilder
    var nativeCitySearchSuggestions: some View {
        ForEach(Array(inlineSortedSearchResults.prefix(8))) { result in
            Button {
                guard !inlineIsLoadingCity else { return }
                Task {
                    await inlineSelectSearchResult(result)
                }
            } label: {
                nativeCitySearchSuggestionRow(for: result)
            }
            .disabled(inlineIsLoadingCity)
        }
    }

    private func nativeCitySearchSuggestionRow(for result: CitySearchResult) -> some View {
        let existing = inlineIsExistingCity(result)

        return HStack(spacing: 10) {
            Image(systemName: existing ? "checkmark.circle.fill" : "magnifyingglass")
                .foregroundStyle(existing ? theme.colors.secondaryText : theme.colors.primaryText.opacity(0.7))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.avenir(.body, weight: .medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(.avenir(.caption, weight: .regular))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if existing {
                Text(localizedString("Added", locale: locale))
                    .font(.avenir(.caption2, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)
            } else if inlineIsLoadingCity {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
    }

    func inlineIsExistingCity(_ result: CitySearchResult) -> Bool {
        let name = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        let data = inlineAddTargetListID.map { weatherService.weatherData(for: $0) } ?? weatherService.cityWeatherData
        return data.contains(where: { $0.city.name == name && $0.city.country == country })
    }

    var inlineSortedSearchResults: [CitySearchResult] {
        inlineSearchManager.searchResults.sorted { a, b in
            let aExists = inlineIsExistingCity(a)
            let bExists = inlineIsExistingCity(b)
            if aExists != bExists { return aExists }
            return false
        }
    }

    func activateInlineSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            tappedCity = nil
            showingInlineSearch = true
        }
    }

    func dismissInlineSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingInlineSearch = false
        }
        resetNativeCitySearch()
    }

    func resetNativeCitySearch() {
        inlineSearchText = ""
        inlineSearchManager.search(query: "")
        inlineAddTargetListID = nil
        inlineSearchSelectionIndex = 0
    }

    func moveInlineSearchSelection(_ delta: Int) {
        let count = min(6, inlineSortedSearchResults.count)
        guard count > 0 else { return }
        inlineSearchSelectionIndex = (inlineSearchSelectionIndex + delta + count) % count
    }

    func confirmInlineSearchSelection() {
        let results = Array(inlineSortedSearchResults.prefix(6))
        guard results.indices.contains(inlineSearchSelectionIndex), !inlineIsLoadingCity else { return }
        let result = results[inlineSearchSelectionIndex]
        Task {
            await inlineSelectSearchResult(result)
        }
    }

    func inlineSelectSearchResult(_ result: CitySearchResult) async {
        inlineIsLoadingCity = true
        defer { inlineIsLoadingCity = false }

        let cityName = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle

        let targetListID = inlineAddTargetListID
        let targetData = targetListID.map { weatherService.weatherData(for: $0) } ?? weatherService.cityWeatherData

        // Check if city already exists
        if let existingCity = targetData.first(where: { $0.city.name == cityName && $0.city.country == country }) {
            if let targetListID {
                inlineAddTargetListID = nil
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingInlineSearch = false
                    inlineSearchText = ""
                }
                revealCityOnMap(existingCity, in: targetListID)
                return
            }
            handleInlineSearchCitySelected(existingCity)
            return
        }

        // Resolve coordinates
        guard let coordinate = await inlineSearchManager.resolveCoordinate(for: result) else {
            return
        }

        // Create and fetch weather for new city
        let tempCity = City(name: cityName, country: country, latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
            return
        }

        if let targetListID {
            await weatherService.addCityToList(tempCityWeather.city, listID: targetListID)
            inlineAddTargetListID = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchText = ""
            }
            revealCityOnMap(tempCityWeather, in: targetListID)
        } else {
            handleInlineSearchCitySelected(tempCityWeather)
        }
    }

    private func handleInlineSearchCitySelected(_ cityWeather: CityWeather) {
        if selectedTab == 1 {
            // On map: show as preview marker with expanded card
            previewCity = cityWeather
            previewSearchText = cityWeather.city.name
            tappedCity = cityWeather
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchText = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                centerOnCityTrigger = cityWeather
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingMapExpandedCard = true
                }
            }
        } else {
            addCityDetailCity = cityWeather
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchText = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showingAddCityDetail = true
            }
        }
    }


}
