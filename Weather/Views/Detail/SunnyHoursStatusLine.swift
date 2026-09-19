//
//  SunnyHoursStatusLine.swift
//  Weather
//
//  Purpose: Renders the shared highlighted sunny-hours phrase used by a
//  selected Map place and the large forecast-report hero.
//

import SwiftUI

// MARK: - Shared Sunny-Hours Status

/// A compact, localized sunny-hours phrase: an outlined sun followed by a
/// highlighted count and the secondary copy “of sun”.
///
/// Keeping this in one component ensures the Detail hero and Map floating
/// card present the same metric with identical hierarchy and spacing.
struct SunnyHoursStatusLine: View {
  let hours: Double

  @Environment(\.appTheme) private var theme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.locale) private var locale

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: "sun.max")
        .font(.body.weight(.semibold))
        .foregroundStyle(theme.colors.dotSun)

      Text(attributedStatusText)
        .font(.body)
        .foregroundStyle(theme.colors.secondaryText)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }
    .minimumScaleFactor(0.75)

  }

  /// Keeps the highlighted count as a movable placeholder inside one
  /// localized sentence. Languages that place the descriptive phrase before
  /// the duration can therefore reorder it without losing the visual emphasis.
  private var attributedStatusText: AttributedString {
    let count = Int64(hours.rounded())
    var hourResource: LocalizedStringResource = "\(count) hours"
    hourResource.locale = locale
    var emphasizedHours = AttributedString(String(localized: hourResource))
    emphasizedHours.font = .body.weight(.semibold)
    emphasizedHours.foregroundColor = theme.colors.dotSun

    var resource: LocalizedStringResource = "\(emphasizedHours) of sun"
    resource.locale = locale
    return AttributedString(localized: resource)
  }
}
