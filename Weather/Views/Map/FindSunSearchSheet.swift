import CoreLocation
import SwiftUI
import UIKit

// MARK: - Find Sun Sheet

/// `alert(item:)` needs an identifiable value. Wrapping a string in this type
/// also makes clearing the error explicit rather than treating empty text as a
/// special case.
struct MapUIError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(
        title: String = "Unable to Update Places",
        message: String
    ) {
        self.title = title
        self.message = message
    }
}

/// A compact native sheet for choosing the spatial source of a sunny-place
/// search. Country and continent selections execute immediately, while Map
/// area and device-location scopes retain their explicit search affordance.
struct MapSunSearchSheet: View {
    let viewport: MapViewport?
    /// The physical location orders the full Country picker by proximity.
    let currentLocationCoordinate: CLLocationCoordinate2D?
    let canSearchNearMe: Bool
    let locale: Locale
    let runSearch: (MapSunQueryScope) -> Void

    /// The scope is the only local draft state. Geographic choices are complete
    /// queries by themselves, so selecting one runs it immediately instead of
    /// requiring a redundant confirmation row.
    @State private var scope: SunSearchScope

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(
        initialScope: SunSearchScope,
        viewport: MapViewport?,
        currentLocationCoordinate: CLLocationCoordinate2D?,
        canSearchNearMe: Bool,
        locale: Locale,
        runSearch: @escaping (MapSunQueryScope) -> Void
    ) {
        self.viewport = viewport
        self.currentLocationCoordinate = currentLocationCoordinate
        self.canSearchNearMe = canSearchNearMe
        self.locale = locale
        self.runSearch = runSearch
        _scope = State(initialValue: initialScope)
    }

    private var canSubmitCurrentScope: Bool {
        // Only these two scopes expose the explicit bottom search button. The
        // country and continent rows each supply the complete scope directly.
        switch scope {
        case .area: viewport != nil
        case .nearMe: canSearchNearMe
        case .country, .continent: false
        }
    }

    private var hasFatalCatalogIssue: Bool {
        CountryCityCatalog.dataIssues.contains { issue in
            switch issue {
            case .resourceMissing, .unreadableResource, .noValidCities:
                true
            case .invalidRows:
                false
            }
        }
    }

    private var searchButtonTitle: LocalizedStringKey {
        switch scope {
        case .area: "Search in This Area"
        case .nearMe:
            canSearchNearMe ? "Search Nearby Places" : "Enable Location Access"
        // These scopes execute from their picker rows and never render this
        // label; keeping the switch exhaustive avoids an optional title.
        case .country, .continent: "Find Sun"
        }
    }

    private var searchButtonSymbol: String {
        scope == .nearMe && !canSearchNearMe
            ? "location.fill"
            : "magnifyingglass"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Search in", selection: $scope) {
                        ForEach(SunSearchScope.allCases) { scope in
                            Text(scope.title(locale: locale)).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(theme.colors.settingsRowFill)

                switch scope {
                case .area:
                    areaControls
                case .nearMe:
                    nearMeControls
                case .country:
                    countryControls
                case .continent:
                    continentControls
                }

                submitControls
            }
            .weatherScrollableBackground()
            .tint(theme.colors.accent)
            .navigationTitle("Find Sun")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
    }

    private var areaControls: some View {
        Section {
            Text("Checks the 25 largest cities in the visible map area for sunny conditions.")
                .font(.body)
                .foregroundStyle(theme.colors.secondaryText)
        }
        .listRowBackground(theme.colors.settingsRowFill)
    }

    @ViewBuilder
    private var nearMeControls: some View {
        Section {
            Text(
                String(
                    format: localizedString(
                        "Checks the 25 largest cities within %@ km of your current location for sunny conditions.",
                        locale: locale
                    ),
                    locale: locale,
                    MapSunQueryScope.nearMeRadiusKilometers
                        .formatted(.number.locale(locale))
                )
            )
                .font(.body)
                .foregroundStyle(theme.colors.secondaryText)

            if !canSearchNearMe {
                Text("Allow location access in Settings to search nearby.")
                    .font(.footnote)
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .listRowBackground(theme.colors.settingsRowFill)
    }

    private var countryControls: some View {
        Section {
            NavigationLink {
                MapSunCountryPicker(
                    currentLocationCoordinate: currentLocationCoordinate,
                    locale: locale,
                    selectCountry: { country in
                        runAndDismiss(.country(country))
                    }
                )
            } label: {
                Label(
                    localizedString("Pick a Country", locale: locale),
                    systemImage: "flag"
                )
                .foregroundStyle(theme.colors.primaryText)
            }
            .disabled(hasFatalCatalogIssue)
        }
        .listRowBackground(theme.colors.settingsRowFill)
    }

    private var continentControls: some View {
        Section {
            ForEach(ContinentPlacesOption.allCases) { continent in
                Button {
                    runAndDismiss(.continent(continent))
                } label: {
                    HStack {
                        Text(continent.localizedName(locale: locale))
                            .foregroundStyle(theme.colors.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(theme.colors.secondaryText)

                    }
                }

            }
        }
        .disabled(hasFatalCatalogIssue)
        .listRowBackground(theme.colors.settingsRowFill)
    }

    @ViewBuilder
    private var submitControls: some View {
        switch scope {
        case .area, .nearMe:
            Section {
                Button(action: submitOrOpenLocationSettings) {
                    Label(searchButtonTitle, systemImage: searchButtonSymbol)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canSubmitCurrentScope && scope != .nearMe)
            }
            .listRowBackground(theme.colors.settingsRowFill)
        case .country, .continent:
            EmptyView()
        }
    }

    /// Runs one fully-defined scope and closes the entire Find Sun sheet. This
    /// closure is owned by the sheet, so a country picker only supplies data
    /// and never has to coordinate nested dismiss actions itself.
    private func runAndDismiss(_ query: MapSunQueryScope) {
        runSearch(query)
        dismiss()
    }

    private func submitCurrentScope() {
        switch scope {
        case .area:
            runAndDismiss(.area)
        case .nearMe:
            runAndDismiss(
                .nearMe(kilometers: MapSunQueryScope.nearMeRadiusKilometers)
            )
        case .country, .continent:
            // Geographic rows execute immediately, so there is no stale draft
            // selection for an explicit search button to submit.
            return
        }
    }

    private func submitOrOpenLocationSettings() {
        guard scope == .nearMe, !canSearchNearMe else {
            submitCurrentScope()
            return
        }
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(settingsURL)
    }
}

/// Country choice is a pushed searchable screen, keeping Find Sun's scope
/// sheet compact while still supporting the full country catalog. Choosing a
/// row immediately executes the country search through the parent sheet.
private struct MapSunCountryPicker: View {
    let currentLocationCoordinate: CLLocationCoordinate2D?
    let locale: Locale
    let selectCountry: (CountryPlacesOption) -> Void

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.appTheme) private var theme

    private var countries: [CountryPlacesOption] {
        // Search both localized and canonical English names so a saved app
        // language never makes a country impossible to find by a familiar name.
        let allCountries = CountryCityCatalog.countries(
            near: currentLocationCoordinate,
            locale: locale
        )
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allCountries }
        return allCountries.filter {
            $0.localizedName(locale: locale).localizedCaseInsensitiveContains(trimmedQuery)
                || $0.englishName.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        List(countries) { country in
            Button {
                selectCountry(country)
            } label: {
                HStack {
                    Text(country.localizedName(locale: locale))
                        .foregroundStyle(theme.colors.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)

                }
            }

            .listRowBackground(theme.colors.settingsRowFill)
        }
        .listStyle(.insetGrouped)
        .weatherScrollableBackground()
        .tint(theme.colors.accent)
        .navigationTitle(localizedString("Pick a Country", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search countries")
        // Set focus after this pushed screen appears, rather than trying to
        // focus a search field that does not yet exist in the hierarchy.
        .searchFocused($isSearchFocused)
        .defaultFocus($isSearchFocused, true)
    }
}
