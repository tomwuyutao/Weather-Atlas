//
//  Haptics.swift
//  Weather
//
//  Purpose: Centralizes the app's lightweight haptic feedback so feature views
//  can request feedback without owning UIKit generator details.
//

import UIKit

enum Haptics {
    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
