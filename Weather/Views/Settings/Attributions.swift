//
//  Attributions.swift
//  Weather
//
//  Purpose: Presents the app's data providers, their legal sources, and
//  official product information in one consistently styled destination.
//

import SwiftUI
import WeatherKit

// MARK: - Attributions Destination

/// Groups every provider by the app feature it supports. Each group follows
/// the same Data, optional Legal Sources, and About structure so provenance is
/// easy to scan and each external link has a predictable purpose.
struct AttributionsView: View {
    let weatherAttribution: WeatherAttribution?

    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            weatherSection

            attributionSection(
                "Maps",
                dataValue: "Apple Maps",
                dataSystemImage: "map",
                legalURL: URL(
                    string: "https://www.apple.com/legal/internet-services/maps/legal-en.html"
                ),
                aboutTitle: "About MapKit",
                aboutURL: URL(
                    string: "https://developer.apple.com/documentation/mapkit/"
                )
            )

            attributionSection(
                "Search",
                dataValue: "Apple Maps and Open-Meteo",
                dataSystemImage: "magnifyingglass",
                legalURL: URL(string: "https://open-meteo.com/en/terms"),
                aboutTitle: "About Open-Meteo",
                aboutURL: URL(
                    string: "https://open-meteo.com/en/docs/geocoding-api"
                )
            )

            attributionSection(
                "Cities Data",
                dataValue: "SimpleMaps World Cities",
                dataSystemImage: "building.2",
                legalURL: URL(string: "https://simplemaps.com/data/license"),
                aboutTitle: "About SimpleMaps",
                aboutURL: URL(
                    string: "https://simplemaps.com/data/world-cities"
                )
            )

            attributionSection(
                "City Name Translations",
                dataValue: "GeoNames",
                dataSystemImage: "character.bubble",
                legalURL: URL(string: "https://www.geonames.org/about.html"),
                aboutTitle: "About GeoNames",
                aboutURL: URL(string: "https://www.geonames.org/")
            )
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.background)
        .weatherContentColumn(standardMaximumWidth: .infinity)
        .navigationTitle("Attributions")
    }

    /// WeatherKit supplies the required localized Apple Weather mark and a
    /// locale-specific legal page. A text fallback keeps the Data row complete
    /// while that independent request is still loading or unavailable.
    private var weatherSection: some View {
        Section {
            LabeledContent {
                WeatherDataSourceMark(attribution: weatherAttribution)
            } label: {
                attributionLabel("Data", systemImage: "cloud.sun")
            }

            if let legalPageURL = weatherAttribution?.legalPageURL {
                attributionLink(
                    "Legal Sources",
                    systemImage: "doc.text",
                    url: legalPageURL
                )
            }

            attributionLink(
                "About WeatherKit",
                systemImage: "info.circle",
                url: URL(string: "https://developer.apple.com/weatherkit/")
            )
        } header: {
            attributionHeader("Weather")
        }
        .listRowBackground(theme.colors.settingsRowFill)
    }

    private func attributionSection(
        _ title: LocalizedStringKey,
        dataValue: String,
        dataSystemImage: String,
        legalURL: URL?,
        aboutTitle: LocalizedStringKey,
        aboutURL: URL?
    ) -> some View {
        Section {
            LabeledContent {
                Text(dataValue)
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.trailing)
            } label: {
                attributionLabel("Data", systemImage: dataSystemImage)
            }

            if let legalURL {
                attributionLink(
                    "Legal Sources",
                    systemImage: "doc.text",
                    url: legalURL
                )
            }

            if let aboutURL {
                attributionLink(
                    aboutTitle,
                    systemImage: "info.circle",
                    url: aboutURL
                )
            }
        } header: {
            attributionHeader(title)
        }
        .listRowBackground(theme.colors.settingsRowFill)
    }

    private func attributionHeader(
        _ title: LocalizedStringKey
    ) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(theme.colors.primaryText)
    }

    private func attributionLabel(
        _ title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        Label {
            Text(title)
                .foregroundStyle(theme.colors.primaryText)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(theme.colors.dotSun)
        }
    }

    private func attributionLink(
        _ title: LocalizedStringKey,
        systemImage: String,
        url: URL?
    ) -> some View {
        Button {
            guard let url else { return }
            openURL(url)
        } label: {
            HStack {
                attributionLabel(title, systemImage: systemImage)
                Spacer(minLength: 8)
                Text("View")
                    .foregroundStyle(theme.colors.secondaryText)
                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }
}

// MARK: - Apple Weather Mark

/// Displays the official WeatherKit mark without making the whole Data row a
/// second link to the same legal destination shown immediately below it.
private struct WeatherDataSourceMark: View {
    let attribution: WeatherAttribution?

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let attribution {
            AsyncImage(url: markURL(for: attribution)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: 100,
                            maxHeight: 17,
                            alignment: .trailing
                        )
                case .empty:
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 24, minHeight: 24)
                case .failure:
                    providerName(for: attribution)
                @unknown default:
                    providerName(for: attribution)
                }
            }
        } else {
            Text(" Weather")
                .foregroundStyle(theme.colors.secondaryText)
        }
    }

    private func providerName(
        for attribution: WeatherAttribution
    ) -> some View {
        Text(attribution.serviceName)
            .foregroundStyle(theme.colors.secondaryText)
    }

    /// WeatherKit provides separate light and dark artwork, so the source mark
    /// stays legible in every app appearance.
    private func markURL(for attribution: WeatherAttribution) -> URL {
        colorScheme == .dark
            ? attribution.combinedMarkDarkURL
            : attribution.combinedMarkLightURL
    }
}

#if DEBUG

#Preview("Attributions") {
    NavigationStack {
        AttributionsView(weatherAttribution: nil)
    }
}
#endif
