//
//  ResponsiveLayout.swift
//  Weather
//
//  Purpose: Defines device- and window-level layout decisions shared by
//  multiple screens.
//

import SwiftUI
import UIKit

/// Identifies a genuinely landscape iPad window, including resized Stage Manager
/// scenes, instead of relying on a size class that can remain regular.
func usesIPadLandscapeLayout(for size: CGSize) -> Bool {
    UIDevice.current.userInterfaceIdiom == .pad && size.width > size.height
}
