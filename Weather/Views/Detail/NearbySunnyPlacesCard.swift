//
//  NearbySunnyPlacesCard.swift
//  Weather
//
//  Purpose: Presents nearby World Cities recommendations using the same
//  ranking as Best Sunny Places, with each city's distance from the reference.
//

import SwiftUI

// MARK: - Nearby Sunny Recommendations

/// A persistent card showing nearby places with more selected-day sunny hours
/// than the report's reference place. It displays fetched recommendations;
/// it does not search.
struct NearbySunnyPlacesCard: View {
  /// The card is a quick local scan, not a second full results screen.
  private static let maxRecommendations = 3

  // MARK: - Inputs and User Preferences

  /// Pre-ranked results supplied by `WeatherModel` for the selected day.
  let recommendations: [NearestSunnyPlaceResult]
  let locationStatus: LocationProviderStatus
  /// Only Your Location needs permission recovery; place reports already carry
  /// an exact coordinate and must never fall back to the device coordinate.
  let requiresCurrentLocation: Bool
  /// A non-nil name changes row distances from “your location” to that place.
  let distanceReferenceName: String?
  let isLoading: Bool
  let hasCompletedSearch: Bool
  let errorMessage: String?
  let requestLocation: () -> Void
  let openSettings: () -> Void
  let viewOnMap: () -> Void

  @Environment(\.appTheme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.locale) private var locale
  @AppStorage("distanceUnit")
  private var distanceUnitRaw = DistanceUnit.defaultRawValue

  /// The card can be waiting while its task runs or while its origin is being
  /// handed to the search. Both phases use the same compact loading layout.

  // MARK: - Presentation

  var body: some View {
    VStack(
      alignment: .leading,
      spacing: WeatherCardLayout.contentSpacing
    ) {
      WeatherCardHeader(
        icon: "location.magnifyingglass",
        title: "Nearby Sunnier Places"
      )

      cardContent
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

  // MARK: - Content States

  @ViewBuilder
  private var cardContent: some View {
    if !(
      // `WeatherModel` has already excluded places that do not improve on the
      // reference place's sunny-hour total. This report is only a compact
      // preview; the Map receives the full eligible result list through the
      // action closure when the person wants to explore more choices.
      Array(recommendations.prefix(Self.maxRecommendations))).isEmpty
    {
      // Render each discovery as native value navigation. Unlike saved
      // places, no bookmark action appears: these are suggestion rows.
      VStack(spacing: 0) {
        VStack(spacing: 0) {
          ForEach(
            (
              // `WeatherModel` has already excluded places that do not improve on the
              // reference place's sunny-hour total. This report is only a compact
              // preview; the Map receives the full eligible result list through the
              // action closure when the person wants to explore more choices.
              Array(recommendations.prefix(Self.maxRecommendations)))
          ) { recommendation in
            resultRow(recommendation)
            if recommendation.id
              != (
              // `WeatherModel` has already excluded places that do not improve on the
              // reference place's sunny-hour total. This report is only a compact
              // preview; the Map receives the full eligible result list through the
              // action closure when the person wants to explore more choices.
              Array(recommendations.prefix(Self.maxRecommendations))).last?.id
            {
              Divider()
                .padding(
                  .leading,
                  WeatherCardLayout.leadingIconWidth
                    + WeatherCardLayout.headerSpacing
                )
            }
          }
        }

        // A partial forecast failure must not distract from usable nearby
        // results. The card only explains an error when it has no result
        // to show, preserving this branch as a concise recommendation list.
        Button(action: viewOnMap) {
          SecondaryTextActionLabel(
            title: "View on Map",
            systemImage: "chevron.right"
          )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
      }
    } else if (
      // `WeatherModel` has already excluded places that do not improve on the
      // reference place's sunny-hour total. This report is only a compact
      // preview; the Map receives the full eligible result list through the
      // action closure when the person wants to explore more choices.
      Array(recommendations.prefix(Self.maxRecommendations))).isEmpty
      && (isLoading
        || ((!requiresCurrentLocation
          || [LocationProviderStatus.ready, .readyWithoutMetadata].contains(locationStatus))
          && !hasCompletedSearch
          && errorMessage == nil))
    {
      (HStack(spacing: WeatherCardLayout.headerSpacing) {
        ProgressView()
          .frame(
            width: WeatherCardLayout.leadingIconWidth,
            alignment: .leading
          )

        Text("Loading nearby sunnier places…")
          .font(.callout)
          .foregroundStyle(theme.colors.secondaryText)
      }
      .frame(maxWidth: .infinity, alignment: .leading))

    } else if let errorMessage {
      Text(errorMessage)
        .font(.callout)
        .foregroundStyle(theme.colors.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else if requiresCurrentLocation
      && [LocationProviderStatus.denied, .restricted, .servicesDisabled].contains(locationStatus)
    {
      (VStack(alignment: .leading, spacing: 12) {
        Text(
          (locationStatus == .denied
            ? localizedString(
              "Location access is off. Allow it in Settings to show your local timeline and nearby sunnier places.",
              locale: locale
            )
            : localizedString(
              "Current location is unavailable on this device.",
              locale: locale
            ))
        )
        .font(.callout)
        .foregroundStyle(theme.colors.secondaryText)

        Button(action: (openSettings)) {
          Label(("Open Settings"), systemImage: ("gearshape"))
        }
        .weatherGlassActionStyle()
      }
      .frame(maxWidth: .infinity, alignment: .leading))
    } else if requiresCurrentLocation
      && ![LocationProviderStatus.ready, .readyWithoutMetadata].contains(locationStatus)
    {
      (VStack(alignment: .leading, spacing: 12) {
        Text(
          (localizedString(
            "Use your location to find nearby places with more sunny hours.",
            locale: locale
          ))
        )
        .font(.callout)
        .foregroundStyle(theme.colors.secondaryText)

        Button(action: (requestLocation)) {
          Label(("Use Current Location"), systemImage: ("location"))
        }
        .weatherGlassActionStyle()
      }
      .frame(maxWidth: .infinity, alignment: .leading))
    } else if hasCompletedSearch {
      Text(
        localizedString(
          "No nearby place has more sunny hours on this date.",
          locale: locale
        )
      )
      .font(.callout)
      .foregroundStyle(theme.colors.secondaryText)
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      (HStack(spacing: WeatherCardLayout.headerSpacing) {
        ProgressView()
          .frame(
            width: WeatherCardLayout.leadingIconWidth,
            alignment: .leading
          )

        Text("Loading nearby sunnier places…")
          .font(.callout)
          .foregroundStyle(theme.colors.secondaryText)
      }
      .frame(maxWidth: .infinity, alignment: .leading))
    }
  }

  // MARK: - Recommendation Rows and Recovery Actions

  private func resultRow(
    _ recommendation: NearestSunnyPlaceResult
  ) -> some View {
    // The row mirrors `SavedPlacesSunnyPlaceRow`: fixed icon column, regular city
    // name, and a trailing total of sunny hours. Its extra line is the local distance.
    NavigationLink(value: AppRoute.place(id: recommendation.id)) {
      HStack(spacing: WeatherCardLayout.headerSpacing) {
        if recommendation.recommendation.symbolName.isEmpty {
          Color.clear
            .frame(
              width: WeatherCardLayout.leadingIconWidth,
              height: 1,
              alignment: .leading
            )
        } else {
          Image(systemName: recommendation.recommendation.symbolName)
            // Current local Today uses WeatherKit's live symbol;
            // an unavailable observation does not fall back to a
            // daily icon.
            .modifier(
              WeatherIconStyleModifier(
                tone: recommendation.recommendation.condition?.iconTone
                  ?? .cloudy,
                symbolName: nil
              )
            )
            .font(.callout.weight(.medium))
            .frame(
              width: WeatherCardLayout.leadingIconWidth,
              alignment: .leading
            )
        }

        VStack(alignment: .leading, spacing: 3) {
          Text(
            recommendation.recommendation.cityWeather.city.displayName
          )
          .font(.body)
          .foregroundStyle(theme.colors.primaryText)
          .lineLimit(2)

          Text(distanceLabel(for: recommendation))
            .font(.caption)
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(2)
        }

        Spacer(minLength: 8)

        Text(
          ({ () -> String in
            let hours = recommendation.recommendation.sunnyHourCount
            return String(
              format: localizedString("%@ h", locale: locale),
              locale: locale,
              hours.formatted(
                .number
                  .grouping(.never)
                  .precision(.fractionLength(hours.rounded() == hours ? 0 : 1))
                  .locale(locale)
              )
            )
          }())
        )
        .font(.body)
        .monospacedDigit()
        .foregroundStyle(theme.colors.primaryText)
        .lineLimit(1)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .padding(.vertical, 6)

  }

  /// Keeps the complete distance phrase localizable while changing only its
  /// reference from the user to the place whose report is open.
  private func distanceLabel(
    for recommendation: NearestSunnyPlaceResult
  ) -> String {
    let unit = DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    let value =
      unit == .kilometers
      ? recommendation.distanceKilometers
      : recommendation.distanceKilometers * 0.621_371
    let distance = "\(Int(value.rounded())) \(unit == .kilometers ? "km" : "mi")"
    guard let distanceReferenceName else {
      return localizedString(
        "\(distance) from your location",
        locale: locale
      )
    }
    return localizedString(
      "\(distance) from \(distanceReferenceName)",
      locale: locale
    )
  }

}

// MARK: - Xcode Previews

#if DEBUG
  #Preview(
    "Nearby Sunnier Places – Loading",
    traits: .fixedLayout(width: 390, height: 150)
  ) {
    NearbySunnyPlacesCard(
      recommendations: [],
      locationStatus: .ready,
      requiresCurrentLocation: true,
      distanceReferenceName: nil,
      isLoading: true,
      hasCompletedSearch: false,
      errorMessage: nil,
      requestLocation: {},
      openSettings: {},
      viewOnMap: {}
    )
    .padding()
    .background(AppPalette.light.background)
    .environment(\.appTheme, .shared)
    .environment(\.locale, Locale(identifier: "en"))
    .preferredColorScheme(.light)
  }
#endif
