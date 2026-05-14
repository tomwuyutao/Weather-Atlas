//
//  PlatformFeedback.swift
//  Weather
//

import SwiftUI

enum PlatformFeedback {
    static func lightImpact() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
