//
//  AppPalette.swift
//  Weather
//
//  Purpose: Defines the app's complete color palette once for both the main app
//  and the widget extension.
//

import SwiftUI
import UIKit

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
        let cloudIcon: Color
        let moonIcon: Color
        let settingsRow: Color
        let shadow: Color
        let tutorialBackground: Color
    }

    static let light = Values(
        titleText: Color(hex: 0x262626),
        secondaryText: Color(hex: 0x6D6D6D),
        background: Color(hex: 0xFAF8F2),
        destructive: Color(hex: 0xD03D3B),
        dotSun: Color(hex: 0xFBC056),
        dotPartlyCloudy: Color(hex: 0xFAD85F),
        dotCloudy: Color(hex: 0xF4EFE4),
        dotRain: Color(hex: 0x4D70D4),
        dotDrizzle: Color(hex: 0x62B9D2),
        cloudIcon: Color(hex: 0x0F4A9C),
        moonIcon: Color(hex: 0xD05FF8),
        settingsRow: Color(hex: 0xF4EFE4),
        shadow: Color(hex: 0x000000),
        tutorialBackground: Color(hex: 0x244F9C)
    )

    static let dark = Values(
        titleText: Color(hex: 0xFEFEFE),
        secondaryText: Color(hex: 0x929292),
        background: Color(hex: 0x262626),
        destructive: Color(hex: 0xD03D3B),
        dotSun: Color(hex: 0xFBC056),
        dotPartlyCloudy: Color(hex: 0xFAD85F),
        dotCloudy: Color(hex: 0xF4EFE4),
        dotRain: Color(hex: 0x8FA8E8),
        dotDrizzle: Color(hex: 0x62B9D2),
        cloudIcon: Color(hex: 0x0F4A9C),
        moonIcon: Color(hex: 0xD05FF8),
        settingsRow: Color(hex: 0x302F2C),
        shadow: Color(hex: 0x000000),
        tutorialBackground: Color(hex: 0x244F9C)
    )

    static func values(for colorScheme: ColorScheme) -> Values {
        colorScheme == .dark ? dark : light
    }

    static func increasedContrastValues(for colorScheme: ColorScheme) -> Values {
        let palette = values(for: colorScheme)
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
                cloudIcon: palette.cloudIcon.interpolated(with: palette.titleText, by: 0.55),
                moonIcon: palette.moonIcon,
                settingsRow: palette.settingsRow,
                shadow: palette.shadow,
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
            cloudIcon: palette.cloudIcon,
            moonIcon: palette.moonIcon.interpolated(with: palette.titleText, by: 0.15),
            settingsRow: palette.settingsRow,
            shadow: palette.shadow,
            tutorialBackground: palette.tutorialBackground
        )
    }
}

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
