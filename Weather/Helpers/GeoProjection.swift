//
//  GeoProjection.swift
//  Weather
//
//  Web Mercator projection for converting geographic coordinates
//  to SVG pixel coordinates and screen coordinates.
//

import Foundation
import CoreGraphics

struct GeoProjection {
    // SVG canvas dimensions
    static let svgWidth: CGFloat = 1009.6727
    static let svgHeight: CGFloat = 665.96301
    
    // geoViewBox bounds: minLon, maxLat, maxLon, minLat
    static let minLon: CGFloat = -169.110266
    static let maxLat: CGFloat = 83.600842
    static let maxLon: CGFloat = 190.486279
    static let minLat: CGFloat = -58.508473
    
    // Precomputed values
    static let lonRange: CGFloat = maxLon - minLon
    static let mercMaxLat: CGFloat = mercator(latitude: Double(maxLat))
    static let mercMinLat: CGFloat = mercator(latitude: Double(minLat))
    static let mercRange: CGFloat = mercMaxLat - mercMinLat
    
    /// Web Mercator projection for latitude
    static func mercator(latitude: Double) -> CGFloat {
        let latRad = latitude * .pi / 360.0
        return CGFloat(log(tan(.pi / 4.0 + latRad)))
    }
    
    /// Convert geographic (lat, lon) to SVG pixel coordinates
    static func geoToSVG(latitude: Double, longitude: Double) -> CGPoint {
        let x = (CGFloat(longitude) - minLon) / lonRange * svgWidth
        let mercLat = mercator(latitude: latitude)
        let y = (mercMaxLat - mercLat) / mercRange * svgHeight
        return CGPoint(x: x, y: y)
    }
    
    /// Convert SVG pixel coordinates to screen coordinates
    static func svgToScreen(svgPoint: CGPoint, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(
            x: svgPoint.x * scale + offset.width,
            y: svgPoint.y * scale + offset.height
        )
    }
    
    /// Convert geographic (lat, lon) directly to screen coordinates
    static func geoToScreen(
        latitude: Double,
        longitude: Double,
        scale: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        svgToScreen(
            svgPoint: geoToSVG(latitude: latitude, longitude: longitude),
            scale: scale,
            offset: offset
        )
    }
}
