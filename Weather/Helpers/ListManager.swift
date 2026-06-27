//
//  ListManager.swift
//  Weather
//
//  Purpose: Lets users edit saved city lists, rename lists, reorder cities,
//  and manage translated country/list names.
//

import SwiftUI
#if canImport(Translation)
import Translation
#endif

// MARK: - Translation Cache

struct CountryCityTranslationCache {
    static let shared = CountryCityTranslationCache()

    private let storageKey = "countryCityNameTranslations"

    func key(for city: City, targetLanguageIdentifier: String) -> String {
        [
            targetLanguageIdentifier,
            city.country,
            city.name,
            String(format: "%.4f", city.latitude),
            String(format: "%.4f", city.longitude)
        ].joined(separator: "|")
    }

    func name(forKey key: String) -> String? {
        load()[key]
    }

    func setName(_ name: String, forKey key: String) {
        var values = load()
        values[key] = name
        save(values)
    }

    private func load() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values
    }

    private func save(_ values: [String: String]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - List Manager

extension ContentView {

    var sidebarLists: [CityListID] {
        _ = listOrderRevision
        return CityListID.allLists
    }

    func sidebarCities(for listID: CityListID) -> [CityWeather] {
        _ = cityOrderRevision
        return weatherService.weatherData(for: listID)
    }

    func sidebarCityCount(for listID: CityListID) -> Int {
        let cities = sidebarCities(for: listID)
        return cities.isEmpty ? weatherService.cityListCoordinates(for: listID).count : cities.count
    }

    func refreshSidebarListOrder() {
        listOrderRevision += 1
        #if os(iOS)
        AppDelegate.updateHomeScreenListShortcuts()
        #endif
    }

    func refreshSidebarCityOrder() {
        cityOrderRevision += 1
    }

    @ViewBuilder
    func listActions(for listID: CityListID) -> some View {
        Button {
            beginRenamingList(listID)
        } label: {
            Label {
                Text(localizedString("Rename", locale: locale))
            } icon: {
                Image(systemName: "pencil")
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)

        Button {
            beginAddingCity(to: listID)
        } label: {
            Label {
                Text(localizedString("Add City", locale: locale))
            } icon: {
                Image(systemName: "plus")
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)

        Button {
            weatherService.deleteList(listID)
            refreshSidebarListOrder()
        } label: {
            Label {
                Text(localizedString("Delete", locale: locale))
            } icon: {
                Image(systemName: "trash")
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)
    }

    @ViewBuilder
    func cityActions(for city: CityWeather, in listID: CityListID) -> some View {
        Button {
            beginRenamingCity(city, in: listID)
        } label: {
            Label {
                Text(localizedString("Rename", locale: locale))
            } icon: {
                Image(systemName: "pencil")
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)

        Button {
            weatherService.removeCity(city, from: listID)
            refreshSidebarCityOrder()
        } label: {
            Label {
                Text(localizedString("Delete", locale: locale))
            } icon: {
                Image(systemName: "trash")
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)
    }

    func createListAtBottom() {
        let newList = CityListID.createList(name: localizedString("New List", locale: locale))
        refreshSidebarListOrder()
        sidebarExpandedListIDs.insert(newList.rawValue)
        listToRenameID = newList
        renameAlertText = newList.localizedDisplayName(locale: locale)
        showingRenameAlert = true
    }

    func beginCreatingListFromSwitcher() {
        beginCreatingCustomList()
    }

    func beginCreatingListFromSwitcherWithMenu() {
        sidebarNewListName = ""
        countryListInitialCountry = nil
        #if os(iOS)
        if shouldUseIPadLayout {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                iPadSidebarVisibility = .all
                iPadPreferredCompactColumn = .sidebar
            }
        } else {
            withAnimation(.smooth(duration: 0.24)) {
                showingMapSidebar = true
            }
        }
        #else
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            macSidebarVisibility = .all
        }
        #endif

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showingAddListTypeMenu = true
        }
    }

    func beginCreatingCustomList() {
        sidebarNewListName = ""
        sidebarShowingAddListAlert = true
    }

    func beginCreatingCountryList(initialCountry: CountryCityGroup? = nil) {
        countryListInitialCountry = initialCountry
        countryListSearchMode = true
        countryListPreviewCountry = initialCountry
        if let initialCountry {
            countryListPreviewCityCount = countryListClampedCityCount(15, for: initialCountry)
        } else {
            countryListPreviewCityCount = 15
        }
        showingCountryListBuilder = false
        showingMapSidebar = false
        showingMapExpandedCard = false
        showingCityDetail = false
        tappedCity = nil
        inlineSearchText = initialCountry?.name ?? ""

        #if os(iOS)
        pushIPhoneRoute(.map)
        #endif

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingInlineSearch = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            inlineSearchFieldPresented = true
        }

        if initialCountry != nil {
            centerMapOnDots(useListCoordinates: true)
        }
    }

    func commitCountryList(_ country: CountryCityGroup, cityCount: Int) {
        addCountry(country, cityCount: cityCount, to: nil)
    }

    func addCountry(_ country: CountryCityGroup, cityCount: Int, to listID: CityListID?) {
        let resolvedCountry = CountryCityCatalog.shared.countryWithCities(for: country) ?? country
        let cities = Array(resolvedCountry.cities.prefix(cityCount))
        guard !cities.isEmpty else { return }
        Task {
            let displayCities = await translatedCountryListCitiesIfNeeded(cities)
            let targetList: CityListID
            if let listID {
                await weatherService.addCities(displayCities, to: listID)
                targetList = listID
            } else {
                targetList = await weatherService.createCustomList(name: resolvedCountry.name, cities: displayCities)
            }

            await MainActor.run {
                refreshSidebarListOrder()
                refreshSidebarCityOrder()
                sidebarExpandedListIDs.insert(targetList.rawValue)
                countryListSearchMode = false
                countryListPreviewCountry = nil
                inlineSearchText = ""
                showingInlineSearch = false
                inlineSearchFieldPresented = false
                inlineAddTargetListID = nil
                recenterOnAllCities = true
                PlatformFeedback.lightImpact()
            }
        }
    }

    func translatedCountryListCitiesIfNeeded(_ cities: [City]) async -> [City] {
        let languageCode = (UserDefaults.standard.string(forKey: "appLanguage") ?? "en")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !languageCode.isEmpty, languageCode != "en" else { return cities }

        #if canImport(Translation)
        if #available(iOS 26.0, macOS 26.0, *) {
            return await translateCountryListCities(cities, targetLanguageIdentifier: languageCode)
        }
        #endif

        return cities
    }

    #if canImport(Translation)
    @available(iOS 26.0, macOS 26.0, *)
    private func translateCountryListCities(_ cities: [City], targetLanguageIdentifier: String) async -> [City] {
        let cache = CountryCityTranslationCache.shared
        let cacheKeys = cities.map { cache.key(for: $0, targetLanguageIdentifier: targetLanguageIdentifier) }
        var translatedNames = cities.enumerated().map { index, city in
            cache.name(forKey: cacheKeys[index]) ?? city.name
        }

        let missingRequests = cities.enumerated().compactMap { index, city -> (index: Int, request: TranslationSession.Request)? in
            guard cache.name(forKey: cacheKeys[index]) == nil else { return nil }
            return (
                index,
                TranslationSession.Request(
                    sourceText: city.name,
                    clientIdentifier: String(index)
                )
            )
        }

        guard !missingRequests.isEmpty else {
            return cities.enumerated().map { index, city in
                City(id: city.id, name: translatedNames[index], country: city.country, latitude: city.latitude, longitude: city.longitude)
            }
        }

        do {
            let session = try TranslationSession(
                installedSource: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: targetLanguageIdentifier)
            )
            let responses = try await session.translations(from: missingRequests.map(\.request))
            for (responseIndex, response) in responses.enumerated() {
                guard missingRequests.indices.contains(responseIndex) else { continue }
                let cityIndex = missingRequests[responseIndex].index
                translatedNames[cityIndex] = response.targetText
                cache.setName(response.targetText, forKey: cacheKeys[cityIndex])
            }
        } catch {
            return cities
        }

        return cities.enumerated().map { index, city in
            City(id: city.id, name: translatedNames[index], country: city.country, latitude: city.latitude, longitude: city.longitude)
        }
    }
    #endif

    func revealCityOnMap(_ city: CityWeather, in listID: CityListID) {
        Task {
            await switchToList(listID)
            let revealedCity = weatherService.cityWeatherData.first {
                $0.city.latitude == city.city.latitude && $0.city.longitude == city.city.longitude
            } ?? city
            #if os(iOS)
            pushIPhoneRoute(.map)
            #else
            showingMapSidebar = false
            #endif
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                showingMapExpandedCard = false
                tappedCity = nil
            }
            centerOnCityTrigger = revealedCity
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                showMapMarkerCard(revealedCity, expanded: false, focusesMarker: true)
            }
        }
    }

    func revealDefaultCityOnMap(_ city: City, in listID: CityListID) {
        Task {
            #if os(iOS)
            pushIPhoneRoute(.map)
            #else
            showingMapSidebar = false
            #endif

            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                showingMapExpandedCard = false
                tappedCity = nil
            }

            let revealedCity = await weatherService.switchList(to: listID, prioritizing: city)
            recenterOnAllCities = true
            refreshSidebarCityOrder()

            guard let revealedCity else { return }
            centerOnCityTrigger = revealedCity
            try? await Task.sleep(for: .milliseconds(350))
            await MainActor.run {
                showMapMarkerCard(revealedCity, expanded: false, focusesMarker: true)
            }
        }
    }

    func commitListManagerNewList() {
        let trimmed = sidebarNewListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newList = CityListID.createList(name: trimmed)
        refreshSidebarListOrder()
        sidebarExpandedListIDs.insert(newList.rawValue)
        sidebarNewListName = ""
    }

    func switchToList(_ listID: CityListID) async {
        guard listID.rawValue != weatherService.activeListID.rawValue else { return }
        await weatherService.switchList(to: listID)
        recenterOnAllCities = true
    }

    private func beginRenamingList(_ listID: CityListID) {
        cityToRename = nil
        cityToRenameListID = nil
        showingCityRenameAlert = false
        listToRenameID = listID
        renameAlertText = listID.localizedDisplayName(locale: locale)
        showingRenameAlert = true
    }

    private func beginRenamingCity(_ city: CityWeather, in listID: CityListID) {
        listToRenameID = nil
        showingRenameAlert = false
        cityToRename = city
        cityToRenameListID = listID
        cityRenameText = city.city.localizedName(locale: locale)
        showingCityRenameAlert = true
    }

    private func beginAddingCity(to listID: CityListID) {
        inlineAddTargetListID = listID
        #if os(iOS)
        pushIPhoneRoute(.map)
        #else
        showingMapSidebar = false
        #endif
        inlineSearchText = ""
        activateInlineSearch()
    }
}
#Preview("List Manager") {
    #if os(iOS)
    NavigationStack {
        ContentView().iPhoneNativeListManager
    }
    #else
    ContentView()
        .macListManagerSidebar
        .frame(width: 280, height: 520)
    #endif
}

#if os(macOS) || os(iOS)
extension ContentView {

    var macListManagerSidebar: some View {
        #if os(iOS)
        Group {
            if shouldUseIPadLayout {
                List {
                    Section {
                        iOSSidebarListRows
                    }
                }
                .listStyle(.sidebar)
                .tint(theme.colors.primaryText)
            } else {
                List {
                    Section {
                        iOSSidebarListRows
                    }
                    .listRowBackground(iPhoneListManagerBackground)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(iPhoneListManagerBackground)
                .tint(theme.colors.accent)
            }
        }
        .environment(\.editMode, $sidebarEditMode)
        .onAppear {
            if sidebarExpandedListIDs.isEmpty {
                sidebarExpandedListIDs.insert(weatherService.activeListID.rawValue)
            }
        }
        #else
        List(selection: $macSidebarSelection) {
            Section(localizedString("Lists", locale: locale)) {
                macSidebarSelectableListRows
            }
        }
        .listStyle(.sidebar)
        .tint(theme.colors.accent)
        .onAppear {
            if sidebarExpandedListIDs.isEmpty {
                sidebarExpandedListIDs.insert(weatherService.activeListID.rawValue)
            }
        }
        .onChange(of: macSidebarSelection) { _, newSelection in
            handleMacSidebarSelection(newSelection)
        }
        #endif
    }

    private var sidebarRowsHideWeatherDecorations: Bool {
        #if os(iOS)
        sidebarEditMode.isEditing
        #else
        false
        #endif
    }

    @ViewBuilder
    private var iOSSidebarListRows: some View {
        ForEach(sidebarLists) { listID in
            DisclosureGroup(isExpanded: macSidebarListExpansionBinding(for: listID)) {
                let cities = sidebarCities(for: listID)
                if cities.isEmpty {
                    let defaultCities = weatherService.cityListCoordinates(for: listID)
                    if defaultCities.isEmpty {
                        Text(localizedString("No cities", locale: locale))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                            .padding(.leading, 22)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(defaultCities) { city in
                            Button {
                                revealDefaultCityOnMap(city, in: listID)
                            } label: {
                                iOSSidebarDefaultCityRow(city)
                            }
                            .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                        }
                    }
                } else {
                    ForEach(cities) { city in
                        Button {
                            revealCityOnMap(city, in: listID)
                        } label: {
                            iOSSidebarCityRow(city)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            cityActions(for: city, in: listID)
                        }
                        .listRowSeparator(.hidden)
                    }
                    .onMove { source, destination in
                        moveMacSidebarCities(in: listID, from: source, to: destination)
                    }
                    .onDelete { offsets in
                        deleteMacSidebarCities(in: listID, at: offsets)
                    }
                }
            } label: {
                iOSSidebarListHeader(listID)
                    .contextMenu {
                        listActions(for: listID)
                    }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(shouldUseIPadLayout
                ? EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14)
                : EdgeInsets(top: 6, leading: 28, bottom: 6, trailing: 28)
            )
            .task(id: listID.rawValue) {
                await weatherService.fetchWeatherForList(listID)
                await MainActor.run {
                    refreshSidebarCityOrder()
                }
            }
        }
        .onMove(perform: moveMacSidebarLists)
        .onDelete(perform: deleteMacSidebarLists)
    }

    private func iOSSidebarListHeader(_ listID: CityListID) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !sidebarRowsHideWeatherDecorations {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10, height: 18)
                }

                Text(listID.localizedDisplayName(locale: locale))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if !sidebarRowsHideWeatherDecorations {
                    Text("\(sidebarCityCount(for: listID))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.colors.mapLand, in: Capsule())
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(theme.colors.primaryText.opacity(0.18))
                .frame(height: 1)
                .padding(.leading, shouldUseIPadLayout ? -10 : -10)
                .padding(.trailing, shouldUseIPadLayout ? -25 : -26)
        }
        .contentShape(Rectangle())
    }

    private func iOSSidebarDefaultCityRow(_ city: City) -> some View {
        HStack(spacing: 10) {
            if !sidebarRowsHideWeatherDecorations {
                Circle()
                    .fill(theme.colors.secondaryText.opacity(0.45))
                    .frame(width: 10, height: 10)
                    .frame(width: 10, alignment: .center)
            }

            Text(city.localizedName(locale: locale))
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 10)
        }
        .padding(.vertical, 9)
        .padding(.leading, shouldUseIPadLayout ? -20 : -18)
        .contentShape(Rectangle())
    }

    private func iOSSidebarCityRow(_ city: CityWeather) -> some View {
        let dotColor = city.weatherIcon.contains("moon") ? theme.colors.moonIconColor : city.condition.dotColor(for: theme.colors)

        return HStack(spacing: 10) {
            if !sidebarRowsHideWeatherDecorations {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: dotColor.opacity(0.35), radius: 3)
                    .frame(width: 10, alignment: .center)
            }

            Text(city.city.localizedName(locale: locale))
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 10)

            if !sidebarRowsHideWeatherDecorations {
                Text(tempUnit.display(city.temperature))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
        .padding(.leading, shouldUseIPadLayout ? -20 : -18)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var macSidebarSelectableListRows: some View {
        ForEach(sidebarLists) { listID in
            DisclosureGroup(isExpanded: macSidebarListExpansionBinding(for: listID)) {
                let cities = sidebarCities(for: listID)
                if cities.isEmpty {
                    let defaultCities = weatherService.cityListCoordinates(for: listID)
                    if defaultCities.isEmpty {
                        Text(localizedString("No cities", locale: locale))
                            .foregroundStyle(.secondary)
                            .tag("empty:\(listID.rawValue)")
                    } else {
                        ForEach(defaultCities) { city in
                            macSidebarDefaultCityRow(city)
                                .tag("loading:\(listID.rawValue):\(city.id.uuidString)")
                        }
                    }
                } else {
                    ForEach(cities) { city in
                        macSidebarWeatherCityRow(city)
                            .tag(macSidebarCityContextID(city, in: listID))
                            .contextMenu {
                                cityActions(for: city, in: listID)
                            }
                    }
                    .onMove { source, destination in
                        moveMacSidebarCities(in: listID, from: source, to: destination)
                    }
                    .onDelete { offsets in
                        deleteMacSidebarCities(in: listID, at: offsets)
                    }
                }
            } label: {
                macSidebarListHeader(listID)
            }
            .tag(macSidebarListContextID(listID))
            .contextMenu {
                listActions(for: listID)
            }
        }
        .onMove(perform: moveMacSidebarLists)
        .onDelete(perform: deleteMacSidebarLists)
    }

    private func macSidebarListHeader(_ listID: CityListID) -> some View {
        HStack(spacing: 8) {
            Text(listID.localizedDisplayName(locale: locale))
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text("\(sidebarCityCount(for: listID))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .offset(x: 1)
        }
        .padding(.leading, 6)
        .contentShape(Rectangle())
    }

    private func macSidebarDefaultCityRow(_ city: City) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(.secondary.opacity(0.42))
                .frame(width: 7, height: 7)
            Text(city.localizedName(locale: locale))
                .font(.headline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
    }

    private func macSidebarWeatherCityRow(_ city: CityWeather) -> some View {
        let dotColor = city.weatherIcon.contains("moon") ? theme.colors.moonIconColor : city.condition.dotColor(for: theme.colors)

        return HStack(spacing: 7) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: dotColor.opacity(0.3), radius: 2)

            Text(city.city.localizedName(locale: locale))
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)

            Spacer(minLength: 4)
        }
        .padding(.vertical, 2)
    }

    private func moveMacSidebarLists(from source: IndexSet, to destination: Int) {
        weatherService.moveLists(from: source, to: destination)
        refreshSidebarListOrder()
        PlatformFeedback.lightImpact()
    }

    private func deleteMacSidebarLists(at offsets: IndexSet) {
        let lists = sidebarLists
        for index in offsets {
            guard lists.indices.contains(index) else { continue }
            weatherService.deleteList(lists[index])
        }
        refreshSidebarListOrder()
        PlatformFeedback.lightImpact()
    }

    private func moveMacSidebarCities(in listID: CityListID, from source: IndexSet, to destination: Int) {
        weatherService.moveCity(in: listID, from: source, to: destination)
        refreshSidebarCityOrder()
        PlatformFeedback.lightImpact()
    }

    private func deleteMacSidebarCities(in listID: CityListID, at offsets: IndexSet) {
        let cities = sidebarCities(for: listID)
        for index in offsets {
            guard cities.indices.contains(index) else { continue }
            weatherService.removeCity(cities[index], from: listID)
        }
        refreshSidebarCityOrder()
        PlatformFeedback.lightImpact()
    }

    private func macSidebarListExpansionBinding(for listID: CityListID) -> Binding<Bool> {
        Binding {
            sidebarExpandedListIDs.contains(listID.rawValue)
        } set: { isExpanded in
            if isExpanded {
                sidebarExpandedListIDs.insert(listID.rawValue)
                Task { await weatherService.fetchWeatherForList(listID) }
            } else {
                sidebarExpandedListIDs.remove(listID.rawValue)
            }
        }
    }

    private func handleMacSidebarSelection(_ selection: String?) {
        guard let selection else { return }
        defer {
            DispatchQueue.main.async {
                macSidebarSelection = nil
            }
        }

        let parts = selection.split(separator: ":").map(String.init)
        guard let kind = parts.first else { return }

        if kind == "list", parts.count == 2,
           let listID = CityListID.allLists.first(where: { $0.rawValue == parts[1] }),
           listID != weatherService.activeListID {
            Task { await switchToList(listID) }
            return
        }

        if kind == "city", parts.count == 3,
           let listID = CityListID.allLists.first(where: { $0.rawValue == parts[1] }),
           let city = weatherService.weatherData(for: listID).first(where: { $0.id.uuidString == parts[2] }) {
            revealCityOnMap(city, in: listID)
            return
        }

        if kind == "loading", parts.count == 3,
           let listID = CityListID.allLists.first(where: { $0.rawValue == parts[1] }),
           let city = weatherService.cityListCoordinates(for: listID).first(where: { $0.id.uuidString == parts[2] }) {
            revealDefaultCityOnMap(city, in: listID)
        }
    }

    private func macSidebarListContextID(_ listID: CityListID) -> String {
        "list:\(listID.rawValue)"
    }

    private func macSidebarCityContextID(_ city: CityWeather, in listID: CityListID) -> String {
        "city:\(listID.rawValue):\(city.id.uuidString)"
    }
}
#endif
#if os(iOS)
#Preview("iOS List Manager") {
    NavigationStack {
        ContentView().iPhoneNativeListManager
    }
}
#elseif os(macOS)
#Preview("Sidebar") {
    ContentView()
        .macListManagerSidebar
        .frame(width: 280, height: 520)
}
#endif
