//
//  NearbyDiscoverySettingsSheet.swift
//  Weather
//
//  Purpose: Provides native nearby-discovery controls and a live MapKit
//  preview of the population-ranked city candidate area.
//

import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Preferences

/// Native discrete radius choices for nearby city discovery.
nonisolated enum NearbyDiscoveryRadius: Double, CaseIterable, Codable, Identifiable, Sendable {
    case kilometers25 = 25
    case kilometers50 = 50
    case kilometers100 = 100
    case kilometers200 = 200
    case kilometers500 = 500

    var id: Self { self }
    var kilometers: Double { rawValue }
    var meters: CLLocationDistance { kilometers * 1_000 }
    var measurement: Measurement<UnitLength> {
        Measurement(value: kilometers, unit: .kilometers)
    }
}

/// Persistable nearby-discovery choices owned by the app model.
nonisolated struct NearbyDiscoveryPreferences: Codable, Equatable, Hashable, Sendable {
    /// Geographic radius applied before any weather request.
    var radius: NearbyDiscoveryRadius = .kilometers100
    /// Whether candidates must match the current coordinate's ISO country.
    var limitToCurrentCountry = false
}

/// Stable inputs that restart only the candidate-prefilter task.
nonisolated private struct NearbyDiscoveryQuery: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let radiusKilometers: Double
    let isoCountryCode: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Mutually exclusive states for the dataset-backed map preview.
nonisolated private enum NearbyDiscoveryPreviewState: Equatable, Sendable {
    case waitingForLocation
    case waitingForCountry
    case loading
    case loaded([NearbyWorldCityCandidate])
    case failed

    var candidates: [NearbyWorldCityCandidate] {
        if case .loaded(let candidates) = self {
            return candidates
        }
        return []
    }
}

// MARK: - Settings Sheet

/// Native modal form for configuring nearby discovery.
///
/// The sheet mutates caller-owned preferences, requests location only from an
/// explicit button, and queries local catalog data without fetching weather.
struct NearbyDiscoverySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @Binding private var preferences: NearbyDiscoveryPreferences
    @Binding private var isEnabled: Bool
    let locationProvider: LocationProvider
    let catalog: WorldCitiesCatalog

    @State private var previewState: NearbyDiscoveryPreviewState = .waitingForLocation
    @State private var cameraPosition: MapCameraPosition = .automatic

    /// Creates a settings sheet suitable for an item-driven presentation route.
    init(
        preferences: Binding<NearbyDiscoveryPreferences>,
        isEnabled: Binding<Bool>,
        locationProvider: LocationProvider,
        catalog: WorldCitiesCatalog = .shared
    ) {
        _preferences = preferences
        _isEnabled = isEnabled
        self.locationProvider = locationProvider
        self.catalog = catalog
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Nearby Recommendations",
                        isOn: $isEnabled
                    )
                } footer: {
                    Text(
                        "When enabled, Weather Atlas updates nearby recommendations after launch if location access was already granted."
                    )
                }
                locationSection
                searchAreaSection
                previewSection
                methodSection
            }
            .weatherAtlasScrollableBackground()
            .navigationTitle("Nearby Discovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .task(id: query) {
                await refreshPreview()
            }
        }
    }

    /// Explicit current-location action; it never runs from `onAppear`.
    private var locationSection: some View {
        Section("Current Location") {
            NearbyLocationStatusRow(
                locationProvider: locationProvider,
                locale: locale,
                isNearbyDiscoveryEnabled: $isEnabled
            )
        }
    }

    /// Uses native Form controls for the geographic candidate limit.
    private var searchAreaSection: some View {
        Section {
            Picker("Search Radius", selection: $preferences.radius) {
                ForEach(NearbyDiscoveryRadius.allCases) { radius in
                    Text(
                        radius.measurement,
                        format: .measurement(width: .abbreviated)
                    )
                    .tag(radius)
                }
            }

            if let currentCountryName {
                Toggle(
                    "Limit to \(currentCountryName)",
                    isOn: $preferences.limitToCurrentCountry
                )
            } else {
                Toggle(
                    "Limit to Current Country",
                    isOn: $preferences.limitToCurrentCountry
                )
                // A persisted enabled filter must remain switchable off when
                // reverse geocoding cannot currently resolve a country.
                .disabled(!preferences.limitToCurrentCountry)
            }
        } header: {
            Text("Search Area")
        } footer: {
            countryFilterFooter
        }
    }

    /// Shows a native interactive map only after a coordinate is available.
    @ViewBuilder
    private var previewSection: some View {
        Section {
            if let coordinate = locationProvider.coordinate {
                NearbyDiscoveryMapPreview(
                    cameraPosition: $cameraPosition,
                    center: coordinate,
                    radiusMeters: preferences.radius.meters,
                    candidates: previewState.candidates,
                    isLoading: previewState == .loading
                )
                .listRowInsets(EdgeInsets())

                LabeledContent("Candidate Cities") {
                    switch previewState {
                    case .loading:
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Loading candidate cities")
                    case .loaded(let candidates):
                        Text(candidates.count, format: .number)
                    case .failed:
                        Label("Unavailable", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    case .waitingForCountry:
                        Text("Resolving Country")
                            .foregroundStyle(.secondary)
                    case .waitingForLocation:
                        Text("Location Required")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Location Required",
                    systemImage: "location",
                    description: Text("Use your current location to preview the search radius.")
                )
            }
        } header: {
            Text("Map Preview")
        } footer: {
            previewFooter
        }
    }

    /// Explains the deliberate population prefilter before WeatherKit.
    private var methodSection: some View {
        Section("How Discovery Works") {
            Text(
                "Weather Atlas first finds up to ten of the most populated cities inside this area. Weather is requested only for those candidates, then the sunniest result is recommended."
            )
        }
    }

    /// Country name follows the app's selected locale rather than device-only
    /// global locale state.
    private var currentCountryName: String? {
        guard let country = locationProvider.country else { return nil }
        return locale.localizedString(forRegionCode: country.isoCountryCode)
            ?? country.localizedName
            ?? country.isoCountryCode
    }

    /// A country-restricted query waits for reverse geocoding rather than
    /// silently running without the user's chosen filter.
    private var query: NearbyDiscoveryQuery? {
        guard let coordinate = locationProvider.coordinate else { return nil }
        let isoCountryCode: String?
        if preferences.limitToCurrentCountry {
            guard let code = locationProvider.country?.isoCountryCode else {
                return nil
            }
            isoCountryCode = code
        } else {
            isoCountryCode = nil
        }

        return NearbyDiscoveryQuery(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusKilometers: preferences.radius.kilometers,
            isoCountryCode: isoCountryCode
        )
    }

    /// Country-filter guidance changes with the provider's stable state.
    @ViewBuilder
    private var countryFilterFooter: some View {
        if locationProvider.country != nil {
            Text("When enabled, cities across a nearby international border are excluded.")
        } else if locationProvider.hasUsableCoordinate {
            Text("The country option becomes available after the current country is resolved.")
        } else {
            Text("A current location is needed before discovery can limit results by country.")
        }
    }

    /// Makes the active map filter explicit without drawing a misleading
    /// approximate national border polygon.
    @ViewBuilder
    private var previewFooter: some View {
        if preferences.limitToCurrentCountry, let currentCountryName {
            Text(
                "The radius circle is unchanged; city markers are limited to \(currentCountryName)."
            )
        } else {
            Text("The circle shows the selected radius. Markers show the population-ranked dataset candidates.")
        }
    }

    /// Queries only local catalog data when coordinate, radius, or country
    /// scope changes.
    private func refreshPreview() async {
        guard let query else {
            previewState = preferences.limitToCurrentCountry
                && locationProvider.hasUsableCoordinate
                ? .waitingForCountry
                : .waitingForLocation
            return
        }

        cameraPosition = .rect(Self.mapRect(for: query))
        previewState = .loading
        do {
            let candidates = try await catalog.nearbyCities(
                centeredAt: query.coordinate,
                radiusKilometers: query.radiusKilometers,
                limitingToISOCountryCode: query.isoCountryCode
            )
            guard !Task.isCancelled else { return }
            previewState = .loaded(candidates)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            previewState = .failed
        }
    }

    /// Fits the full radius using MapKit's projected coordinate system.
    nonisolated private static func mapRect(
        for query: NearbyDiscoveryQuery
    ) -> MKMapRect {
        let centerPoint = MKMapPoint(query.coordinate)
        let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(query.latitude)
        let radiusMapPoints =
            query.radiusKilometers * 1_000 * mapPointsPerMeter * 1.25
        return MKMapRect(
            x: centerPoint.x - radiusMapPoints,
            y: centerPoint.y - radiusMapPoints,
            width: radiusMapPoints * 2,
            height: radiusMapPoints * 2
        )
    }
}

// MARK: - Location Row

/// Native status row that owns its explicit request and Settings actions.
private struct NearbyLocationStatusRow: View {
    @Environment(\.openURL) private var openURL

    let locationProvider: LocationProvider
    let locale: Locale
    @Binding var isNearbyDiscoveryEnabled: Bool

    var body: some View {
        switch locationProvider.status {
        case .checkingAvailability:
            progressRow(title: "Checking Location Services")
        case .requestingAuthorization:
            progressRow(title: "Waiting for Permission")
        case .locating:
            progressRow(title: "Finding Your Location")
        case .resolvingCountry:
            progressRow(title: "Resolving Current Country")
        case .ready:
            Button("Update Current Location", systemImage: "location") {
                enableAndRequestLocation()
            }
        case .readyWithoutCountry:
            VStack(alignment: .leading, spacing: 8) {
                Label("Location Ready", systemImage: "location.fill")
                Text("The country could not be resolved, so country limiting is unavailable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    enableAndRequestLocation()
                }
            }
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label("Location Access Is Off", systemImage: "location.slash")
                Text("Allow location access in Settings to discover nearby cities.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    guard let settingsURL = URL(
                        string: UIApplication.openSettingsURLString
                    ) else {
                        return
                    }
                    openURL(settingsURL)
                }
            }
        case .restricted:
            Label(
                "Location access is restricted by this device.",
                systemImage: "location.slash"
            )
        case .servicesDisabled:
            Label(
                "Location Services are turned off for this device.",
                systemImage: "location.slash"
            )
        case .failed:
            VStack(alignment: .leading, spacing: 8) {
                Label("Location Unavailable", systemImage: "exclamationmark.triangle")
                Button("Try Again") {
                    enableAndRequestLocation()
                }
            }
        case .idle:
            Button("Use Current Location", systemImage: "location") {
                enableAndRequestLocation()
            }
        }
    }

    private func enableAndRequestLocation() {
        isNearbyDiscoveryEnabled = true
        locationProvider.requestCurrentLocation(preferredLocale: locale)
    }

    /// Combines progress and its localized purpose into one VoiceOver element.
    private func progressRow(title: LocalizedStringKey) -> some View {
        HStack {
            ProgressView()
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Map Preview

/// Interactive MapKit preview of radius and country-filtered city candidates.
private struct NearbyDiscoveryMapPreview: View {
    @Binding var cameraPosition: MapCameraPosition

    let center: CLLocationCoordinate2D
    let radiusMeters: CLLocationDistance
    let candidates: [NearbyWorldCityCandidate]
    let isLoading: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        Map(position: $cameraPosition) {
            MapCircle(center: center, radius: radiusMeters)
                .foregroundStyle(.tint.opacity(0.12))
                .stroke(.tint, lineWidth: 2)

            Marker(
                "Current Location",
                systemImage: "location.fill",
                coordinate: center
            )
            .tint(theme.colors.accent)

            ForEach(candidates) { candidate in
                Marker(
                    candidate.city.name,
                    monogram: Text(candidate.city.name.prefix(1)),
                    coordinate: candidate.city.coordinate
                )
                .tint(theme.colors.dotSun)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .aspectRatio(1.25, contentMode: .fit)
        .frame(minHeight: 240, maxHeight: 360)
        .overlay {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding()
                    .background(.regularMaterial, in: .circle)
                    .accessibilityLabel("Updating map preview")
            }
        }
    }
}

// MARK: - Previews

#Preview("Nearby Discovery") {
    @Previewable @State var preferences = NearbyDiscoveryPreferences()

    let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
    let provider = LocationProvider(
        previewStatus: .ready,
        coordinate: london,
        country: CurrentCountry(
            isoCountryCode: "GB",
            localizedName: "United Kingdom"
        )
    )
    let previewCatalog = WorldCitiesCatalog(
        preloadedCities: [
            WorldCityRecord(
                id: "2643743",
                name: "London",
                asciiName: "London",
                countryName: "United Kingdom",
                isoCountryCode: "GB",
                iso3CountryCode: "GBR",
                administrativeArea: "London",
                latitude: 51.5074,
                longitude: -0.1278,
                population: 11_262_000
            ),
            WorldCityRecord(
                id: "2654675",
                name: "Brighton",
                asciiName: "Brighton",
                countryName: "United Kingdom",
                isoCountryCode: "GB",
                iso3CountryCode: "GBR",
                administrativeArea: "Brighton and Hove",
                latitude: 50.8225,
                longitude: -0.1372,
                population: 290_395
            ),
            WorldCityRecord(
                id: "2759794",
                name: "Amsterdam",
                asciiName: "Amsterdam",
                countryName: "Netherlands",
                isoCountryCode: "NL",
                iso3CountryCode: "NLD",
                administrativeArea: "Noord-Holland",
                latitude: 52.3728,
                longitude: 4.8936,
                population: 1_400_000
            )
        ]
    )

    NearbyDiscoverySettingsSheet(
        preferences: $preferences,
        isEnabled: .constant(true),
        locationProvider: provider,
        catalog: previewCatalog
    )
}

#Preview("Location Denied") {
    @Previewable @State var preferences = NearbyDiscoveryPreferences()

    NearbyDiscoverySettingsSheet(
        preferences: $preferences,
        isEnabled: .constant(true),
        locationProvider: LocationProvider(previewStatus: .denied),
        catalog: WorldCitiesCatalog(preloadedCities: [])
    )
}
