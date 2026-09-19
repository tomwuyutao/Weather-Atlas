//
//  ThemeColors.swift
//  Weather
//
//  Purpose: Converts primitive palette values into semantic colors consumed
//  by app and widget views.
//

import SwiftUI
import UIKit

// MARK: - Semantic Colors

struct ThemeColors {
  let usesIncreasedContrast: Bool
  let titleText: Color
  let secondaryText: Color
  let background: Color
  let destructive: Color
  let dotSun: Color
  let dotPartlyCloudy: Color
  let dotCloudy: Color
  let dotRain: Color
  let rainForeground: Color
  let dotDrizzle: Color
  let drizzleForeground: Color
  let moonIconColor: Color
  let settingsRowFill: Color

  var primaryText: Color { titleText }
  var accent: Color { primaryText }

  var noSunTimelineFill: Color {
    let standardFill = AppPalette.light.dotCloudy.interpolated(
      with: background,
      by: 0.40
    )

    guard usesIncreasedContrast else { return standardFill }

    let resolvedFill = UIColor(standardFill)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard
      resolvedFill.getRed(
        &red,
        green: &green,
        blue: &blue,
        alpha: &alpha
      )
    else {
      return AppPalette.light.dotCloudy.interpolated(with: .black, by: 0.08)
    }

    let perceivedBrightness = (red * 0.2126 + green * 0.7152 + blue * 0.0722) * 0.92
    return Color(
      white: Double(max(0, min(1, perceivedBrightness))),
      opacity: Double(alpha)
    )
  }

  var glassFill: Color { background }

  static let sunnyHoursColorScaleMaximum = 10.0

  func sunnyHoursMapDotColor(for sunnyHours: Double) -> Color {
    let fraction = min(
      max(sunnyHours / Self.sunnyHoursColorScaleMaximum, 0),
      1
    )
    let neutralBase = dotCloudy
    guard fraction > 0 else { return neutralBase }

    let curvedFraction = pow(fraction, 1.55)
    let sunnyOpacity = 0.16 + 0.79 * curvedFraction
    return neutralBase.interpolated(with: dotSun, by: sunnyOpacity)
  }

  func weatherIconColor(
    for tone: WeatherIconTone,
    symbolName: String? = nil
  ) -> Color {
    if symbolName?.localizedCaseInsensitiveContains("moon") == true {
      return moonIconColor
    }
    switch tone {
    case .clear:
      return dotSun
    case .partlySunny:
      return dotPartlyCloudy
    case .cloudy:
      return dotCloudy
    case .rain:
      return dotRain
    case .drizzle:
      return dotDrizzle
    }
  }
}

// MARK: - Complete Themes

extension ThemeColors {
  static let light = ThemeColors(palette: AppPalette.light)
  static let dark = ThemeColors(palette: AppPalette.dark)
  static let black = ThemeColors(palette: AppPalette.black)

  static let increasedContrastLight = ThemeColors(
    palette: AppPalette.increasedContrastValues(
      for: AppPalette.light,
      colorScheme: .light
    ),
    usesIncreasedContrast: true
  )

  static let increasedContrastDark = ThemeColors(
    palette: AppPalette.increasedContrastValues(
      for: AppPalette.dark,
      colorScheme: .dark
    ),
    usesIncreasedContrast: true
  )

  static let increasedContrastBlack = ThemeColors(
    palette: AppPalette.increasedContrastValues(
      for: AppPalette.black,
      colorScheme: .dark
    ),
    usesIncreasedContrast: true
  )

  fileprivate init(
    palette: AppPalette.Values,
    usesIncreasedContrast: Bool = false
  ) {
    self.init(
      usesIncreasedContrast: usesIncreasedContrast,
      titleText: palette.titleText,
      secondaryText: palette.secondaryText,
      background: palette.background,
      destructive: palette.destructive,
      dotSun: palette.dotSun,
      dotPartlyCloudy: palette.dotPartlyCloudy,
      dotCloudy: palette.dotCloudy,
      dotRain: palette.dotRain,
      rainForeground: palette.rainForeground,
      dotDrizzle: palette.dotDrizzle,
      drizzleForeground: palette.drizzleForeground,
      moonIconColor: palette.moonIcon,
      settingsRowFill: palette.settingsRow
    )
  }
}
