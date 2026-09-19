//
//  LiquidGlassStyles.swift
//  Weather
//
//  Purpose: Provides the shared Liquid Glass cards and controls, including
//  accessibility and earlier-iOS fallbacks.
//

import SwiftUI

// MARK: - Card Style

private struct GlassCardModifier<Shape: InsettableShape>: ViewModifier {
  @Environment(\.appTheme) private var theme
  @Environment(\.accessibilityReduceTransparency)
  private var reduceTransparency
  let colorScheme: ColorScheme
  let shape: Shape

  @ViewBuilder
  func body(content: Content) -> some View {
    if reduceTransparency {
      content
        .background(theme.colors.glassFill, in: shape)
        .overlay(
          shape.stroke(
            theme.colors.primaryText.opacity(0.18),
            lineWidth: 0.8
          )
        )
    } else if #available(iOS 26.0, *) {
      content.glassEffect(.regular, in: shape)
    } else {
      content
        .background(.ultraThinMaterial, in: shape)
        .background(
          theme.colors.glassFill.opacity(colorScheme == .dark ? 0.30 : 0.38),
          in: shape
        )
    }
  }
}

// MARK: - Action Style

private struct WeatherGlassActionStyleModifier: ViewModifier {
  @Environment(\.accessibilityReduceTransparency)
  private var reduceTransparency

  @ViewBuilder
  func body(content: Content) -> some View {
    if reduceTransparency {
      content
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    } else if #available(iOS 26.0, *) {
      content
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
    } else {
      content
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }
  }
}

// MARK: - View APIs

extension View {
  func detailTranslucentCard<Shape: InsettableShape>(
    colorScheme: ColorScheme,
    in shape: Shape
  ) -> some View {
    modifier(
      GlassCardModifier(
        colorScheme: colorScheme,
        shape: shape
      )
    )
  }

  func weatherGlassActionStyle() -> some View {
    modifier(WeatherGlassActionStyleModifier())
  }
}
