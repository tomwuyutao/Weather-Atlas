//
//  SearchView.swift
//  Weather
//
//  Purpose: Presents Apple Maps and translated Open-Meteo city results, then
//  opens an unsaved city in Detail for an explicit save decision.
//

import CoreLocation
import SwiftUI

struct PlaceSearchView: View {
    let model: WeatherAtlasModel
    @Bindable var router: AppRouter

    @State private var searchManager = CitySearchManager()
    @State private var query = ""
    @State private var isSettled = true
    @State private var loadingResultID: CitySearchResult.ID?
    @State private var selectionTask: Task<Void, Never>?
    @State private var presentedError: PlaceSearchPresentedError?
    @FocusState private var isSearchFocused: Bool

    @Environment(\.locale) private var locale

    var body: some View {
        searchContent
            .weatherAtlasScreenBackground()
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search cities"
            )
            .searchFocused($isSearchFocused)
            .task(id: normalizedQuery) {
                await updateSearch()
            }
            .task(id: router.selectedTab) {
                guard router.selectedTab == .search else { return }
                await Task.yield()
                isSearchFocused = true
            }
            .onDisappear {
                selectionTask?.cancel()
                isSearchFocused = false
            }
            .alert(
                "Search",
                isPresented: errorIsPresented,
                presenting: presentedError
            ) { _ in
                Button("OK") { presentedError = nil }
            } message: { error in
                Text(error.message)
            }
    }

    @ViewBuilder
    private var searchContent: some View {
        if normalizedQuery.isEmpty {
            ContentUnavailableView(
                "Search for a City",
                systemImage: "magnifyingglass",
                description: Text(
                    "Search Apple Maps or Open-Meteo, then review the forecast before saving a place."
                )
            )
        } else if hasNoResults && isSearchInProgress && !hasProviderError {
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if hasNoResults && !hasProviderError {
            ContentUnavailableView.search(text: normalizedQuery)
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            providerSection(
                "Apple Maps",
                results: searchManager.appleResults,
                isSearching: searchManager.isAppleSearching,
                errorMessage: searchManager.appleErrorMessage
            )

            providerSection(
                "Open-Meteo",
                results: searchManager.openMeteoResults,
                isSearching: searchManager.isOpenMeteoSearching,
                errorMessage: searchManager.openMeteoErrorMessage
            )
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .weatherAtlasScrollableBackground()
    }

    @ViewBuilder
    private func providerSection(
        _ title: LocalizedStringKey,
        results: [CitySearchResult],
        isSearching: Bool,
        errorMessage: String?
    ) -> some View {
        if !results.isEmpty || isSearching || errorMessage != nil {
            Section(title) {
                ForEach(results) { result in
                    resultButton(result)
                }

                if isSearching {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func resultButton(_ result: CitySearchResult) -> some View {
        Button {
            select(result)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .foregroundStyle(.primary)

                    if !result.subtitle.isEmpty {
                        Text(result.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if loadingResultID == result.id {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Opening \(result.title)")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(loadingResultID != nil)
        .accessibilityHint("Opens this place's forecast")
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented { presentedError = nil }
            }
        )
    }

    private var hasNoResults: Bool {
        searchManager.appleResults.isEmpty && searchManager.openMeteoResults.isEmpty
    }

    private var isSearchInProgress: Bool {
        !isSettled || searchManager.isAppleSearching || searchManager.isOpenMeteoSearching
    }

    private var hasProviderError: Bool {
        searchManager.appleErrorMessage != nil || searchManager.openMeteoErrorMessage != nil
    }

    @MainActor
    private func updateSearch() async {
        guard !normalizedQuery.isEmpty else {
            searchManager.search(query: "", locale: locale)
            isSettled = true
            return
        }

        isSettled = false
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        let submittedQuery = normalizedQuery
        searchManager.search(query: submittedQuery, locale: locale)
        guard !Task.isCancelled, normalizedQuery == submittedQuery else { return }
        isSettled = true
    }

    @MainActor
    private func select(_ result: CitySearchResult) {
        selectionTask?.cancel()
        selectionTask = Task { @MainActor in
            loadingResultID = result.id
            defer {
                loadingResultID = nil
                selectionTask = nil
            }

            guard let resolvedPlace = await searchManager.resolvePlace(for: result) else {
                guard !Task.isCancelled else { return }
                presentedError = PlaceSearchPresentedError(
                    message: localizedString(
                        "This search result could not be resolved. Please try another result.",
                        locale: locale
                    )
                )
                return
            }
            guard !Task.isCancelled else { return }

            let city = City(
                name: resolvedPlace.cityName,
                country: resolvedPlace.country,
                latitude: resolvedPlace.coordinate.latitude,
                longitude: resolvedPlace.coordinate.longitude,
                timeZoneIdentifier: resolvedPlace.timeZoneIdentifier
            )
            if let savedPlaceID = model.placesStore.savedPlaceID(matching: city) {
                isSearchFocused = false
                router.showMap(placeID: savedPlaceID)
                return
            }
            model.registerTransientSearchCity(city)
            isSearchFocused = false
            router.showMap(previewing: city)
        }
    }
}

private struct PlaceSearchPresentedError: Identifiable {
    let id = UUID()
    let message: String
}
