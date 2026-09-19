//
//  IPadLayout.swift
//  Weather
//
//  Purpose: Keeps information screens readable in regular-width iPad windows.
//

import SwiftUI

// MARK: - Widths

enum IPadLayout {
  static let standardMaximumWidth: CGFloat = 760
  static let landscapeMaximumWidth: CGFloat = 640
}

// MARK: - Content Column

private struct IPadContentColumnModifier: ViewModifier {
  let standardMaximumWidth: CGFloat

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  func body(content: Content) -> some View {
    GeometryReader { geometry in
      content
        .frame(
          maxWidth: horizontalSizeClass == .regular
            && geometry.size.width > geometry.size.height
            ? min(standardMaximumWidth, IPadLayout.landscapeMaximumWidth)
            : standardMaximumWidth,
          maxHeight: .infinity
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

extension View {
  func weatherContentColumn(
    standardMaximumWidth: CGFloat = IPadLayout.standardMaximumWidth
  ) -> some View {
    modifier(
      IPadContentColumnModifier(
        standardMaximumWidth: standardMaximumWidth
      )
    )
  }
}
