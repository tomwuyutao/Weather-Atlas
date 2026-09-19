//
//  AppPalette.swift
//  Weather
//
//  Purpose: Defines the primitive colors shared by the app and widgets.
//

import SwiftUI
import UIKit

// MARK: - Palette Values

enum AppPalette {
  struct Values {
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
    let moonIcon: Color
    let settingsRow: Color
  }

  // MARK: - Base Palettes

  static let light = Values(
    titleText: Color(hex: 0x262626),
    secondaryText: Color(hex: 0x6D6D6D),
    background: Color(hex: 0xFAF8F2),
    destructive: Color(hex: 0xD14D30),
    dotSun: Color(hex: 0xFBC056),
    dotPartlyCloudy: Color(hex: 0xFAE38E),
    dotCloudy: Color(hex: 0xC8C8C8),
    dotRain: Color(hex: 0x5AA4F3),
    rainForeground: Color(hex: 0x5AA4F3),
    dotDrizzle: Color(hex: 0x67D1F0),
    drizzleForeground: Color(hex: 0x67D1F0),
    moonIcon: Color(hex: 0xC985DE),
    settingsRow: Color(hex: 0xF4EFE4)
  )

  static let dark = Values(
    titleText: Color(hex: 0xFEFEFE),
    secondaryText: Color(hex: 0x929292),
    background: Color(hex: 0x262626),
    destructive: Color(hex: 0xD14D30),
    dotSun: Color(hex: 0xFBC056),
    dotPartlyCloudy: Color(hex: 0xFAE38E),
    dotCloudy: Color(hex: 0xC8C8C8),
    dotRain: Color(hex: 0x5AA4F3),
    rainForeground: Color(hex: 0x5AA4F3),
    dotDrizzle: Color(hex: 0x67D1F0),
    drizzleForeground: Color(hex: 0x67D1F0),
    moonIcon: Color(hex: 0xC985DE),
    settingsRow: Color(hex: 0x303030)
  )

  static let black = Values(
    titleText: dark.titleText,
    secondaryText: dark.secondaryText,
    background: Color(hex: 0x000000),
    destructive: dark.destructive,
    dotSun: dark.dotSun,
    dotPartlyCloudy: dark.dotPartlyCloudy,
    dotCloudy: dark.dotCloudy,
    dotRain: dark.dotRain,
    rainForeground: dark.rainForeground,
    dotDrizzle: dark.dotDrizzle,
    drizzleForeground: dark.drizzleForeground,
    moonIcon: dark.moonIcon,
    settingsRow: Color(hex: 0x181818)
  )

  // MARK: - Contrast Resolution

  static func values(
    for colorScheme: ColorScheme,
    contrast: ColorSchemeContrast
  ) -> Values {
    let palette = colorScheme == .dark ? dark : light
    return contrast == .increased
      ? increasedContrastValues(for: palette, colorScheme: colorScheme)
      : palette
  }

  static func increasedContrastValues(
    for palette: Values,
    colorScheme: ColorScheme
  ) -> Values {
    if colorScheme == .dark {
      return Values(
        titleText: palette.titleText,
        secondaryText: palette.secondaryText.interpolated(
          with: palette.titleText,
          by: 0.16
        ),
        background: palette.background,
        destructive: palette.destructive.interpolated(
          with: palette.titleText,
          by: 0.28
        ),
        dotSun: palette.dotSun,
        dotPartlyCloudy: palette.dotPartlyCloudy,
        dotCloudy: palette.dotCloudy,
        dotRain: palette.dotRain,
        rainForeground: palette.rainForeground,
        dotDrizzle: palette.dotDrizzle,
        drizzleForeground: palette.drizzleForeground,
        moonIcon: palette.moonIcon,
        settingsRow: palette.settingsRow
      )
    }

    return Values(
      titleText: palette.titleText,
      secondaryText: palette.secondaryText.interpolated(
        with: palette.titleText,
        by: 0.12
      ),
      background: palette.background,
      destructive: palette.destructive.interpolated(
        with: palette.titleText,
        by: 0.16
      ),
      dotSun: palette.dotSun.interpolated(with: palette.titleText, by: 0.48),
      dotPartlyCloudy: palette.dotPartlyCloudy.interpolated(
        with: palette.titleText,
        by: 0.55
      ),
      dotCloudy: palette.dotCloudy.interpolated(with: palette.titleText, by: 0.66),
      dotRain: palette.dotRain.interpolated(with: palette.titleText, by: 0.16),
      rainForeground: palette.rainForeground.interpolated(
        with: palette.titleText,
        by: 0.40
      ),
      dotDrizzle: palette.dotDrizzle.interpolated(with: palette.titleText, by: 0.36),
      drizzleForeground: palette.drizzleForeground.interpolated(
        with: palette.titleText,
        by: 0.54
      ),
      moonIcon: palette.moonIcon.interpolated(with: palette.titleText, by: 0.15),
      settingsRow: palette.settingsRow
    )
  }
}

// MARK: - Color Construction

extension Color {
  init(hex: UInt32) {
    let red = Double((hex >> 16) & 0xFF) / 255.0
    let green = Double((hex >> 8) & 0xFF) / 255.0
    let blue = Double(hex & 0xFF) / 255.0
    self.init(red: red, green: green, blue: blue)
  }

  func interpolated(with other: Color, by amount: Double) -> Color {
    let fraction = max(0, min(1, amount))
    let first = UIColor(self)
    let second = UIColor(other)
    var red1: CGFloat = 0
    var green1: CGFloat = 0
    var blue1: CGFloat = 0
    var alpha1: CGFloat = 0
    var red2: CGFloat = 0
    var green2: CGFloat = 0
    var blue2: CGFloat = 0
    var alpha2: CGFloat = 0

    guard first.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1),
      second.getRed(&red2, green: &green2, blue: &blue2, alpha: &alpha2)
    else {
      return fraction < 0.5 ? self : other
    }

    return Color(
      red: Double(red1 + (red2 - red1) * fraction),
      green: Double(green1 + (green2 - green1) * fraction),
      blue: Double(blue1 + (blue2 - blue1) * fraction),
      opacity: Double(alpha1 + (alpha2 - alpha1) * fraction)
    )
  }
}
