//
//  ContentView+Search.swift
//  Weather
//
//  Extracted from ContentView.swift
//

import SwiftUI
import CoreLocation

extension ContentView {

    // MARK: - Inline Search Results (shown when typing)

    var iOSInlineSearchResults: some View {
        VStack(spacing: 0) {
            if !inlineSearchManager.searchResults.isEmpty {
                List {
                    ForEach(Array(inlineSortedSearchResults.enumerated()), id: \.element.id) { index, result in
                        let existing = inlineIsExistingCity(result)
                        let isSelected = index == inlineSearchSelectionIndex
                        Button {
                            Task {
                                await inlineSelectSearchResult(result)
                            }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(result.title)
                                    .font(.avenir(.body, weight: existing ? .semibold : .regular))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                if existing {
                                    Text(localizedString("Added", locale: locale))
                                        .font(.avenir(.caption2, weight: .medium))
                                        .foregroundStyle(theme.colors.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(theme.colors.accent.opacity(0.12), in: Capsule())
                                }

                                Spacer()

                                if inlineIsLoadingCity {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(result.subtitle)
                                        .font(.avenir(.caption, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 2)
                            .background {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? theme.colors.accent.opacity(0.18) : Color.clear)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(inlineIsLoadingCity)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        .listRowSeparator(.visible)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 80)
            } else {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    Text(localizedString("No results", locale: locale))
                        .font(.avenir(.title3, weight: .medium))

                    Text(localizedString("Try a different search term", locale: locale))
                        .font(.avenir(.body))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selectedTab == 0 ? theme.colors.background : theme.colors.searchOverlayBackground)
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Country Search Results

    private var filteredCountries: [String] {
        if countrySearchText.isEmpty {
            return allCountries
        }
        return allCountries.filter { $0.localizedCaseInsensitiveContains(countrySearchText) }
    }

    var iOSCountrySearchResults: some View {
        VStack(spacing: 0) {
            if !filteredCountries.isEmpty {
                List {
                    ForEach(filteredCountries, id: \.self) { country in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                pendingCountryList = country
                                countrySearchText = ""
                                countrySearchFocused = false
                                isLoadingPendingCountry = true
                            }
                            Task {
                                visibleListIDs = []
                                await weatherService.addCountryList(country: country)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isLoadingPendingCountry = false
                                }
                                recenterOnAllCities = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Text(country)
                                    .font(.avenir(.body, weight: .regular))
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.visible)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 80)
            } else {
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "globe")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    Text(localizedString("No results", locale: locale))
                        .font(.avenir(.title3, weight: .medium))

                    Text(localizedString("Try a different search term", locale: locale))
                        .font(.avenir(.body))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(selectedTab == 0 ? theme.colors.background : theme.colors.searchOverlayBackground)
        .ignoresSafeArea(edges: .bottom)
    }

    private func selectCountry(_ country: String) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showingCountrySearch = false
            countrySearchText = ""
            countrySearchFocused = false
        }
        withAnimation(.easeOut(duration: 0.15)) {
            listContentOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            visibleListIDs = []
            await weatherService.addCountryList(country: country)
            withAnimation(.easeIn(duration: 0.2)) {
                listContentOpacity = 1
            }
            recenterOnAllCities = true
        }
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
            showingInlineSearch = true
            inlineSearchFocused = true
        }
    }

    func dismissInlineSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingInlineSearch = false
            inlineSearchText = ""
            inlineSearchFocused = false
            inlineAddTargetListID = nil
            inlineSearchSelectionIndex = 0
        }
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
