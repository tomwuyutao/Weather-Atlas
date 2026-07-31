//
//  PlaceSearchView.swift
//  Weather
//
//  Purpose: Provides one reusable, native world-city search experience for
//  both the dedicated search-role tab and the Add Place sheet.
//

import CoreLocation
import SwiftUI

/// Searches the bundled world-city catalog and saves a result to All Places.
///
/// A collection identity is optional and only adds a relationship after the
/// place itself has been saved.
struct PlaceSearchView: View {
    let placesStore: PlacesStore
    let weatherStore: PlaceWeatherStore
    let targetCollectionID: PlaceCollection.ID?
    let onSaved: (City.ID) -> Void

    @State private var searchManager = CitySearchManager()
    @State private var query = ""
    @State private var isSettled = true
    @State private var loadingResultID: CitySearchResult.ID?
    @State private var selectionTask: Task<Void, Never>?
    @State private var presentedError: PlaceSearchPresentedError?
    @Environment(\.locale) private var locale

    init(
        placesStore: PlacesStore,
        weatherStore: PlaceWeatherStore,
        targetCollectionID: PlaceCollection.ID? = nil,
        onSaved: @escaping (City.ID) -> Void
    ) {
        self.placesStore = placesStore
        self.weatherStore = weatherStore
        self.targetCollectionID = targetCollectionID
        self.onSaved = onSaved
    }

    var body: some View {
        searchContent
            .weatherAtlasScreenBackground()
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search cities"
            )
            .task(id: normalizedQuery) {
                await updateSearch()
            }
            .onDisappear {
                selectionTask?.cancel()
            }
            .alert(
                "Search",
                isPresented: errorIsPresented,
                presenting: presentedError
            ) { _ in
                Button("OK") {
                    presentedError = nil
                }
            } message: { presentedError in
                Text(presentedError.message)
            }
    }

    @ViewBuilder
    private var searchContent: some View {
        if normalizedQuery.isEmpty {
            ContentUnavailableView(
                "Search for a City",
                systemImage: "magnifyingglass",
                description: Text(
                    "Search by city name. It will be saved directly to All Places."
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
            if !searchManager.searchResults.isEmpty {
                Section("Results") {
                    ForEach(searchManager.searchResults) { result in
                        resultButton(result)
                    }
                }
            }

            if isSearchInProgress {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Searching for more places…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if let message = searchManager.searchErrorMessage {
                Section("Search Unavailable") {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .weatherAtlasScrollableBackground()
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
                        .accessibilityLabel("Adding \(result.title)")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loadingResultID != nil)
        .accessibilityHint("Saves this place")
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    presentedError = nil
                }
            }
        )
    }

    private var hasNoResults: Bool {
        searchManager.searchResults.isEmpty
    }

    private var isSearchInProgress: Bool {
        !isSettled || searchManager.isSearching
    }

    private var hasProviderError: Bool {
        searchManager.searchErrorMessage != nil
    }

    @MainActor
    private func updateSearch() async {
        searchManager.search(query: "", locale: locale)

        guard !normalizedQuery.isEmpty else {
            isSettled = true
            return
        }

        isSettled = false
        do {
            try await Task.sleep(for: .milliseconds(300))
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

            guard let resolvedPlace = await searchManager.resolvePlace(
                for: result
            ) else {
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
                timeZoneIdentifier: resolvedPlace.timeZoneIdentifier,
                catalogIdentifier: resolvedPlace.catalogIdentifier
            )

            do {
                let savedID = try placesStore.savePlace(
                    city,
                    in: targetCollectionID
                )
                guard let savedCity = placesStore.place(id: savedID)?.city else {
                    throw PlacesStoreError.placeNotFound(savedID)
                }

                query = ""
                onSaved(savedID)
                Task {
                    _ = await weatherStore.refresh(
                        city: savedCity,
                        locale: locale
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                presentedError = PlaceSearchPresentedError(
                    message: localizedPlacesErrorDescription(
                        error,
                        locale: locale
                    )
                )
            }
        }
    }
}

/// Item-driven native alert content for recoverable place-search failures.
private struct PlaceSearchPresentedError: Identifiable {
    let id = UUID()
    let message: String
}
