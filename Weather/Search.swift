//
//  Search.swift
//  Weather
//
//  Native city search and MapKit search plumbing.
//

import SwiftUI
import CoreLocation
import MapKit

// MARK: - Search Result

struct CitySearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    fileprivate let completion: MKLocalSearchCompletion?
    let countryList: CountryCityGroup?

    init(title: String, subtitle: String, completion: MKLocalSearchCompletion) {
        self.id = "city-\(completion.title)-\(completion.subtitle)"
        self.title = title
        self.subtitle = subtitle
        self.completion = completion
        self.countryList = nil
    }

    init(countryList: CountryCityGroup) {
        self.id = "country-\(countryList.id)"
        self.title = countryList.name
        self.subtitle = "Country"
        self.completion = nil
        self.countryList = countryList
    }
}

// MARK: - City Search Manager

@Observable
class CitySearchManager: NSObject, MKLocalSearchCompleterDelegate {
    var searchResults: [CitySearchResult] = []
    private let completer: MKLocalSearchCompleter

    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
        )
    }

    func search(query: String) {
        if query.isEmpty {
            searchResults = []
            return
        }
        completer.queryFragment = query
    }

    func resolveCoordinate(for result: CitySearchResult) async -> CLLocationCoordinate2D? {
        guard let completion = result.completion else { return nil }
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.first?.placemark.location?.coordinate
        } catch {
            return nil
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        searchResults = completer.results.map { completion in
            CitySearchResult(
                title: completion.title,
                subtitle: completion.subtitle,
                completion: completion
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
    }
}

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
        if countryListSearchMode, countryListPreviewCountry != nil {
            content
        } else if showingInlineSearch || inlineSearchFieldPresented {
            content
                .searchable(
                    text: $inlineSearchText,
                    isPresented: $inlineSearchFieldPresented,
                    placement: placement,
                    prompt: Text(localizedString("Search for a city or country", locale: locale))
                )
                .searchSuggestions {
                    if showingInlineSearch || inlineSearchFieldPresented {
                        nativeCitySearchSuggestions
                    }
                }
                .onChange(of: inlineSearchText) { _, newValue in
                    inlineSearchManager.search(query: newValue)
                    inlineSearchSelectionIndex = 0
                }
                .onChange(of: inlineSearchFieldPresented) { _, isPresented in
                    if !isPresented {
                        if countryListSearchMode, countryListPreviewCountry == nil {
                            cancelCountryListPreview()
                            return
                        }
                        dismissNativeCitySearchAndRecenter()
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
        ForEach(Array(inlineSortedSearchResults.prefix(inlineSearchResultLimit).enumerated()), id: \.element.id) { index, result in
            if result.countryList != nil {
                Button {
                    guard !inlineIsLoadingCity else { return }
                    Task {
                        await inlineSelectSearchResult(result)
                    }
                } label: {
                    nativeCitySearchSuggestionRow(for: result, isSelected: index == inlineSearchSelectionIndex)
                }
                .disabled(inlineIsLoadingCity)
                    .listRowBackground(searchSuggestionBackground)
            } else {
                Button {
                    guard !inlineIsLoadingCity else { return }
                    Task {
                        await inlineSelectSearchResult(result)
                    }
                } label: {
                    nativeCitySearchSuggestionRow(for: result, isSelected: index == inlineSearchSelectionIndex)
                }
                .disabled(inlineIsLoadingCity)
                .listRowBackground(searchSuggestionBackground)
            }
        }
    }

    @ViewBuilder
    var countryListSearchSuggestionPanel: some View {
        if countryListSearchMode,
           countryListPreviewCountry == nil,
           !inlineSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !inlineSortedSearchResults.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(inlineSortedSearchResults.prefix(inlineSearchResultLimit).enumerated()), id: \.element.id) { index, result in
                    if result.countryList != nil {
                        Button {
                            Task {
                                await inlineSelectSearchResult(result)
                            }
                        } label: {
                            nativeCitySearchSuggestionRow(for: result, isSelected: index == inlineSearchSelectionIndex)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            Task {
                                await inlineSelectSearchResult(result)
                            }
                        } label: {
                            nativeCitySearchSuggestionRow(for: result, isSelected: index == inlineSearchSelectionIndex)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: 430)
            .background(searchSuggestionBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.38), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.14), radius: 20, y: 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var inlineSearchResultLimit: Int { 8 }

    private var searchSuggestionBackground: Color {
        colorScheme == .dark ? Color(hex: 0x262052) : theme.colors.background
    }

    private var searchSuggestionSelectedBackground: Color {
        colorScheme == .dark ? Color(hex: 0x4A4480).opacity(0.92) : theme.colors.listCardFill.opacity(0.92)
    }

    private var searchSuggestionTitleColor: Color {
        colorScheme == .dark ? .white.opacity(0.92) : theme.colors.primaryText
    }

    private var searchSuggestionSubtitleColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : theme.colors.secondaryText
    }

    private var shouldShowInlineSearchSelectionHighlight: Bool {
        #if os(macOS)
        true
        #elseif os(iOS)
        shouldUseIPadLayout
        #else
        false
        #endif
    }

    private func nativeCitySearchSuggestionRow(for result: CitySearchResult, isSelected: Bool) -> some View {
        let existingListName = inlineExistingCityListName(for: result)
        let isCountryList = result.countryList != nil
        let rowFill = isSelected && shouldShowInlineSearchSelectionHighlight
            ? searchSuggestionSelectedBackground
            : searchSuggestionBackground.opacity(0.88)
        let titleColor = searchSuggestionTitleColor
        let subtitleColor = searchSuggestionSubtitleColor
        let chipFill = theme.colors.accent.opacity(0.18)
        #if os(macOS)
        let rowSpacing: CGFloat = 8
        let titleFont: Font = .system(size: 13, weight: .medium)
        let subtitleFont: Font = .system(size: 11, weight: .regular)
        let statusFont: Font = .system(size: 10, weight: .medium)
        let statusBoldFont: Font = .system(size: 10, weight: .semibold)
        let rowVerticalPadding: CGFloat = 3
        let rowHorizontalPadding: CGFloat = 6
        let rowCornerRadius: CGFloat = 7
        #else
        let rowSpacing: CGFloat = 10
        let titleFont: Font = .avenir(.body, weight: .medium)
        let subtitleFont: Font = .avenir(.caption, weight: .regular)
        let statusFont: Font = .avenir(.caption2, weight: .medium)
        let statusBoldFont: Font = .avenir(.caption2, weight: .bold)
        let rowVerticalPadding: CGFloat = 3
        let rowHorizontalPadding: CGFloat = 8
        let rowCornerRadius: CGFloat = 10
        #endif

        return HStack(spacing: rowSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(titleFont)
                    .foregroundStyle(titleColor)
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isCountryList {
                Text("Country")
                    .font(statusBoldFont)
                    .foregroundStyle(theme.colors.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(chipFill, in: Capsule())
            } else if let existingListName {
                HStack(spacing: 6) {
                    (Text(localizedString("In list", locale: locale) + " ")
                        .font(statusFont)
                    + Text(existingListName)
                        .font(statusBoldFont))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(1)

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(subtitleColor)
                }
            } else if inlineIsLoadingCity {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, rowVerticalPadding)
        .padding(.horizontal, rowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowFill, in: RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
    }

    func countryAddMenu(for country: CountryCityGroup, cityCount: Int? = nil) -> some View {
        Menu {
            ForEach(sidebarLists) { listID in
                Button(listID.localizedDisplayName(locale: locale)) {
                    addCountry(country, cityCount: cityCount ?? defaultCountrySearchCityCount(for: country), to: listID)
                }
            }

            Divider()

            Button("Create New List \"\(country.name)\"") {
                addCountry(country, cityCount: cityCount ?? defaultCountrySearchCityCount(for: country), to: nil)
            }
        } label: {
            Label(localizedString("Add Cities", locale: locale), systemImage: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(theme.colors.accent, in: Capsule())
                .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(inlineIsLoadingCity)
    }

    func defaultCountrySearchCityCount(for country: CountryCityGroup) -> Int {
        let resolvedCountry = CountryCityCatalog.shared.countryWithCities(for: country) ?? country
        return countryListClampedCityCount(15, for: resolvedCountry)
    }

    private func inlineCityIdentity(for result: CitySearchResult) -> (name: String, country: String) {
        if let countryList = result.countryList {
            return (countryList.name, countryList.name)
        }
        let name = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle
        return (name, country)
    }

    func inlineExistingCityListName(for result: CitySearchResult) -> String? {
        guard result.countryList == nil else { return nil }
        let identity = inlineCityIdentity(for: result)
        if let targetListID = inlineAddTargetListID {
            let cities = weatherService.cityListCoordinates(for: targetListID)
            if cities.contains(where: { $0.name == identity.name && $0.country == identity.country }) {
                return targetListID.localizedDisplayName(locale: locale)
            }
            return nil
        }

        return weatherService.listContainingCity(named: identity.name, country: identity.country)?.localizedDisplayName(locale: locale)
    }

    func inlineIsExistingCity(_ result: CitySearchResult) -> Bool {
        inlineExistingCityListName(for: result) != nil
    }

    private func inlineCountryMatch(for result: CitySearchResult) -> CountryCityGroup? {
        if let countryList = result.countryList {
            return countryList
        }

        let titleName = result.title
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? result.title
        return CountryCityCatalog.shared.country(matching: titleName)
    }

    var inlineSortedSearchResults: [CitySearchResult] {
        let countryResults = CountryCityCatalog.shared.searchCountries(matching: inlineSearchText).map {
            CitySearchResult(countryList: $0)
        }
        if countryListSearchMode {
            return countryResults
        }
        let preferredCountryResults = countryResults.filter { result in
            guard let country = result.countryList else { return false }
            return CountryCityCatalog.isPreferredCountryMatch(country, query: inlineSearchText)
        }
        let secondaryCountryResults = countryResults.filter { result in
            guard let country = result.countryList else { return false }
            return !CountryCityCatalog.isPreferredCountryMatch(country, query: inlineSearchText)
        }
        let cityResults = inlineSearchManager.searchResults
            .filter { inlineCountryMatch(for: $0) == nil }
            .sorted { a, b in
            let aExists = inlineIsExistingCity(a)
            let bExists = inlineIsExistingCity(b)
            if aExists != bExists { return aExists }
            return false
        }
        return preferredCountryResults + cityResults + secondaryCountryResults
    }

    func activateInlineSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingMapExpandedCard = false
            tappedCity = nil
            showingInlineSearch = true
        }
        #if os(iOS)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            inlineSearchFieldPresented = true
        }
        #else
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            inlineSearchFieldPresented = true
        }
        #endif
    }

    func dismissInlineSearch() {
        dismissNativeCitySearchAndRecenter()
    }

    func resetNativeCitySearch() {
        inlineSearchText = ""
        inlineSearchManager.search(query: "")
        inlineAddTargetListID = nil
        inlineSearchSelectionIndex = 0
    }

    func dismissNativeCitySearchAndRecenter() {
        let shouldRecenter = showingInlineSearch
            || inlineSearchFieldPresented
            || !inlineSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !inlineSearchManager.searchResults.isEmpty
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingInlineSearch = false
            inlineSearchFieldPresented = false
        }
        resetNativeCitySearch()
        guard shouldRecenter else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            centerMapOnDots(useListCoordinates: true)
        }
    }

    func moveInlineSearchSelection(_ delta: Int) {
        let count = min(inlineSearchResultLimit, inlineSortedSearchResults.count)
        guard count > 0 else { return }
        inlineSearchSelectionIndex = (inlineSearchSelectionIndex + delta + count) % count
    }

    func confirmInlineSearchSelection() {
        let results = Array(inlineSortedSearchResults.prefix(inlineSearchResultLimit))
        guard results.indices.contains(inlineSearchSelectionIndex), !inlineIsLoadingCity else { return }
        let result = results[inlineSearchSelectionIndex]
        Task {
            await inlineSelectSearchResult(result)
        }
    }

    func inlineSelectSearchResult(_ result: CitySearchResult) async {
        if let countryList = inlineCountryMatch(for: result) {
            let selectedCountry = CountryCityCatalog.shared.countryWithCities(for: countryList) ?? countryList
            await MainActor.run {
                countryListSearchMode = true
                countryListPreviewCountry = selectedCountry
                countryListPreviewCityCount = countryListClampedCityCount(countryListPreviewCityCount, for: selectedCountry)
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingInlineSearch = false
                    inlineSearchFieldPresented = false
                    inlineSearchText = ""
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    centerMapOnDots(useListCoordinates: true)
                }
            }
            return
        }

        inlineIsLoadingCity = true
        defer { inlineIsLoadingCity = false }

        let cityName = result.title.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? result.title
        let country = result.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? result.subtitle

        let targetListID = inlineAddTargetListID
        let targetData = targetListID.map { weatherService.weatherData(for: $0) } ?? weatherService.cityWeatherData

        if let existingCity = targetData.first(where: { $0.city.name == cityName && $0.city.country == country }) {
            if let targetListID {
                inlineAddTargetListID = nil
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingInlineSearch = false
                    inlineSearchFieldPresented = false
                    inlineSearchText = ""
                }
                revealCityOnMap(existingCity, in: targetListID)
                return
            }
            handleInlineSearchCitySelected(existingCity)
            return
        }

        guard let coordinate = await inlineSearchManager.resolveCoordinate(for: result) else {
            return
        }

        let tempCity = City(name: cityName, country: country, latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let tempCityWeather = await weatherService.fetchWeatherForCity(tempCity) else {
            return
        }

        if let targetListID {
            await weatherService.addCityToList(tempCityWeather.city, listID: targetListID)
            inlineAddTargetListID = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchFieldPresented = false
                inlineSearchText = ""
            }
            revealCityOnMap(tempCityWeather, in: targetListID)
        } else {
            handleInlineSearchCitySelected(tempCityWeather)
        }
    }

    private func handleInlineSearchCitySelected(_ cityWeather: CityWeather) {
        if selectedTab == 1 {
            previewCity = cityWeather
            previewSearchText = cityWeather.city.name
            tappedCity = cityWeather
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = false
                inlineSearchFieldPresented = false
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
                inlineSearchFieldPresented = false
                inlineSearchText = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showingAddCityDetail = true
                #if os(iOS)
                pushIPhoneRoute(.addCityDetail)
                #endif
            }
        }
    }
}
