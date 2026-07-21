//
//  ConditionalViewModifier.swift
//  Weather
//
//  Purpose: Applies a SwiftUI view transform only when a condition is true.
//

import SwiftUI

extension View {
    @ViewBuilder
    func `if`(_ condition: Bool, transform: (Self) -> some View) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
