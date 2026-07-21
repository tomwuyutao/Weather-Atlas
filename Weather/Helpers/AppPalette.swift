//
//  AppPalette.swift
//  Weather
//
//  Purpose: Defines the app's complete color palette once for both the main app
//  and the widget extension.
//

import SwiftUI
import UIKit

// MARK: - Shared App Palette

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
        let dotDrizzle: Color
        let settingsRow: Color
        let tutorialBackground: Color
    }

    static let light = Values(
        titleText: Color(hex: 0x262626),
        secondaryText: Color(hex: 0x6D6D6D),
        background: Color(hex: 0xFAF8F2),
        destructive: Color(hex: 0xD14D30),
        dotSun: Color(hex: 0xFBC056),
        dotPartlyCloudy: Color(hex: 0xFAE38E),
        dotCloudy: Color(hex: 0xC8C8C8),
        dotRain: Color(hex: 0x5AA4F3),
        dotDrizzle: Color(hex: 0x67D1F0),
        settingsRow: Color(hex: 0xF4EFE4),
        tutorialBackground: Color(hex: 0x244F9C)
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
        dotDrizzle: Color(hex: 0x67D1F0),
        settingsRow: Color(hex: 0x303030),
        tutorialBackground: Color(hex: 0x244F9C)
    )

    // Black keeps the dark palette's content colors while replacing its main
    // canvas with true black for OLED displays and a stronger dark appearance.
    static let black = Values(
        titleText: dark.titleText,
        secondaryText: dark.secondaryText,
        background: Color(hex: 0x000000),
        destructive: dark.destructive,
        dotSun: dark.dotSun,
        dotPartlyCloudy: dark.dotPartlyCloudy,
        dotCloudy: dark.dotCloudy,
        dotRain: dark.dotRain,
        dotDrizzle: dark.dotDrizzle,
        settingsRow: Color(hex: 0x181818),
        tutorialBackground: dark.tutorialBackground
    )

    static func values(for colorScheme: ColorScheme) -> Values {
        colorScheme == .dark ? dark : light
    }

    static func increasedContrastValues(for colorScheme: ColorScheme) -> Values {
        increasedContrastValues(
            for: values(for: colorScheme),
            colorScheme: colorScheme
        )
    }

    static var increasedContrastBlack: Values {
        increasedContrastValues(for: black, colorScheme: .dark)
    }

    private static func increasedContrastValues(
        for palette: Values,
        colorScheme: ColorScheme
    ) -> Values {
        if colorScheme == .dark {
            return Values(
                titleText: palette.titleText,
                secondaryText: palette.secondaryText,
                background: palette.background,
                destructive: palette.destructive.interpolated(with: palette.titleText, by: 0.12),
                dotSun: palette.dotSun,
                dotPartlyCloudy: palette.dotPartlyCloudy,
                dotCloudy: palette.dotCloudy,
                dotRain: palette.dotRain,
                dotDrizzle: palette.dotDrizzle,
                settingsRow: palette.settingsRow,
                tutorialBackground: palette.tutorialBackground
            )
        }

        return Values(
            titleText: palette.titleText,
            secondaryText: palette.secondaryText,
            background: palette.background,
            destructive: palette.destructive.interpolated(with: palette.titleText, by: 0.12),
            dotSun: palette.dotSun.interpolated(with: palette.titleText, by: 0.48),
            dotPartlyCloudy: palette.dotPartlyCloudy.interpolated(with: palette.titleText, by: 0.55),
            dotCloudy: palette.dotCloudy.interpolated(with: palette.titleText, by: 0.66),
            dotRain: palette.dotRain.interpolated(with: palette.titleText, by: 0.10),
            dotDrizzle: palette.dotDrizzle.interpolated(with: palette.titleText, by: 0.35),
            settingsRow: palette.settingsRow,
            tutorialBackground: palette.tutorialBackground
        )
    }
}

// MARK: - Color Construction and Interpolation

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
              second.getRed(&red2, green: &green2, blue: &blue2, alpha: &alpha2) else {
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
