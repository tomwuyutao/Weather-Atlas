//
//  WeatherViewStyles.swift
//  Weather
//
//  Purpose: Provides shared weather-icon and screen-background styling that is
//  independent of the app's Liquid Glass surfaces.
//

import SwiftUI

// MARK: - Weather Icons

struct WeatherIconStyleModifier: ViewModifier {
  @Environment(\.appTheme) private var theme
  let tone: WeatherIconTone
  let symbolName: String?

  func body(content: Content) -> some View {
    content
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(
        theme.colors.weatherIconColor(
          for: tone,
          symbolName: symbolName
        )
      )
  }
}

// MARK: - Screen Backgrounds

private struct ScrollableBackgroundModifier: ViewModifier {
  @Environment(\.appTheme) private var theme

  func body(content: Content) -> some View {
    content
      .scrollContentBackground(.hidden)
      .background(theme.colors.background)
  }
}

private struct ScreenBackgroundModifier: ViewModifier {
  @Environment(\.appTheme) private var theme

  func body(content: Content) -> some View {
    content.background(theme.colors.background.ignoresSafeArea())
  }
}

struct WeatherConditionScreenBackgroundModifier: ViewModifier {
  @Environment(\.appTheme) private var theme
  let tone: WeatherIconTone?
  let symbolName: String?

  func body(content: Content) -> some View {
    content.background(
      ({ () -> Color in
        guard let tone else { return theme.colors.background }
        guard !theme.colors.usesIncreasedContrast else {
          return theme.colors.background
        }
        return theme.colors.weatherIconColor(
          for: tone,
          symbolName: symbolName
        ).interpolated(with: theme.colors.background, by: 0.78)
      }())
      .ignoresSafeArea()
    )
  }
}

extension View {
  func weatherScrollableBackground() -> some View {
    modifier(ScrollableBackgroundModifier())
  }

  func weatherScreenBackground() -> some View {
    modifier(ScreenBackgroundModifier())
  }
}
