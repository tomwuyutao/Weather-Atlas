//
//  WeatherEffectsView.swift
//  Weather
//
//  Animated weather effects for map marker icons.
//

import SwiftUI

// MARK: - Sun Glow Effect

struct SunGlowEffect: View {
    var subtle: Bool = false
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            
            // Slow rotation: 360° per 12 seconds
            let rotationAngle = Angle.degrees(
                now.truncatingRemainder(dividingBy: 12.0) / 12.0 * 360.0
            )
            
            // Pulsing glow: opacity oscillates between 0.15 and 0.4 over 3 seconds
            let pulsePhase = sin(now * 2.0 * .pi / 3.0)
            let baseOpacity = subtle ? 0.15 : 0.275
            let opacityRange = subtle ? 0.06 : 0.125
            let scaleRange = subtle ? 0.05 : 0.1
            let glowOpacity = baseOpacity + opacityRange * pulsePhase
            let glowScale = 1.0 + scaleRange * pulsePhase
            
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.5
                
                let gradient = Gradient(colors: [
                    Color.yellow.opacity(glowOpacity),
                    Color.orange.opacity(glowOpacity * 0.5),
                    Color.clear
                ])
                
                context.fill(
                    Circle().path(in: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )),
                    with: .radialGradient(
                        gradient,
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
            .scaleEffect(glowScale)
            .rotationEffect(rotationAngle)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Rain Drops Effect

struct RainDropsEffect: View {
    var isHeavy: Bool = true
    /// The height of the parent icon frame (used to compute overflow)
    var iconHeight: CGFloat = 32
    
    private var dropCount: Int { isHeavy ? 6 : 3 }
    private var xOffsets: [CGFloat] {
        isHeavy
            ? [0.25, 0.35, 0.5, 0.6, 0.75, 0.45]
            : [0.3, 0.5, 0.65]
    }
    private var basePeriod: Double { isHeavy ? 0.7 : 1.2 }
    
    /// How far below the icon the rain extends
    private var overflowHeight: CGFloat { iconHeight * 0.25 }
    /// Total canvas height: icon area + overflow below
    private var totalHeight: CGFloat { iconHeight + overflowHeight }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            
            Canvas { context, size in
                let scale = size.width / 36.0
                // Rain starts at 75% of the icon height (below cloud)
                let rainTop = iconHeight * 0.75
                // Rain falls all the way to the bottom of the extended canvas
                let rainHeight = size.height - rainTop
                
                for i in 0..<dropCount {
                    let seed = Double(i)
                    let period = basePeriod + seed * 0.15
                    let phase = (now / period + seed * 0.25)
                        .truncatingRemainder(dividingBy: 1.0)
                    
                    let x = size.width * xOffsets[i]
                    let y = rainTop + CGFloat(phase) * rainHeight
                    
                    // Fade in at start, fade out at end
                    let opacity: Double
                    if phase < 0.2 {
                        opacity = phase / 0.2
                    } else if phase > 0.8 {
                        opacity = (1.0 - phase) / 0.2
                    } else {
                        opacity = 1.0
                    }
                    
                    let dropW = 1.5 * scale
                    let dropH = 4.0 * scale
                    let dropRect = CGRect(x: x - dropW / 2, y: y - dropH / 2, width: dropW, height: dropH)
                    let dropPath = Capsule().path(in: dropRect)
                    context.fill(dropPath, with: .color(.cyan.opacity(0.55 * opacity)))
                }
            }
        }
        .frame(height: totalHeight)
        .allowsHitTesting(false)
    }
}

// MARK: - Snowflakes Effect

struct SnowflakesEffect: View {
    var iconHeight: CGFloat = 32
    
    private let flakeCount = 5
    private let xOffsets: [CGFloat] = [0.2, 0.38, 0.55, 0.72, 0.45]
    private let basePeriod: Double = 2.0
    
    /// How far below the icon the snow extends
    private var overflowHeight: CGFloat { iconHeight * 0.25 }
    private var totalHeight: CGFloat { iconHeight + overflowHeight }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            
            Canvas { context, size in
                let scale = size.width / 36.0
                let snowTop = iconHeight * 0.75
                let snowHeight = size.height - snowTop
                
                for i in 0..<flakeCount {
                    let seed = Double(i)
                    let period = basePeriod + seed * 0.3
                    let phase = (now / period + seed * 0.2)
                        .truncatingRemainder(dividingBy: 1.0)
                    
                    // Gentle horizontal drift using sine wave
                    let drift = sin(now * 1.5 + seed * 2.0) * 3.0 * scale
                    let x = size.width * xOffsets[i] + drift
                    let y = snowTop + CGFloat(phase) * snowHeight
                    
                    // Fade in at start, fade out at end
                    let opacity: Double
                    if phase < 0.2 {
                        opacity = phase / 0.2
                    } else if phase > 0.8 {
                        opacity = (1.0 - phase) / 0.2
                    } else {
                        opacity = 1.0
                    }
                    
                    let flakeSize = 2.5 * scale
                    let flakeRect = CGRect(x: x - flakeSize / 2, y: y - flakeSize / 2, width: flakeSize, height: flakeSize)
                    let flakePath = Circle().path(in: flakeRect)
                    context.fill(flakePath, with: .color(.white.opacity(0.6 * opacity)))
                }
            }
        }
        .frame(height: totalHeight)
        .allowsHitTesting(false)
    }
}

// MARK: - Cloud Drift Effect

struct CloudDriftEffect: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            // Gentle horizontal drift: ±3pt over 4 seconds
            let drift = sin(now * 2.0 * .pi / 4.0) * 3.0
            let pulse = sin(now * 2.0 * .pi / 3.0)
            let opacity = 0.18 + 0.07 * pulse
            
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2 + drift, y: size.height / 2)
                let w = size.width * 0.75
                let h = size.height * 0.4
                let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
                let path = Capsule().path(in: rect)
                context.fill(path, with: .color(.white.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Wind Streaks Effect

struct WindStreaksEffect: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            
            Canvas { context, size in
                let scale = size.width / 36.0
                let streaks: [(y: CGFloat, period: Double, seed: Double)] = [
                    (0.3, 1.8, 0.0),
                    (0.5, 1.5, 0.4),
                    (0.7, 2.0, 0.7),
                ]
                
                for streak in streaks {
                    let phase = ((now / streak.period + streak.seed)
                        .truncatingRemainder(dividingBy: 1.0))
                    
                    // Streak sweeps from left to right
                    let streakW = size.width * 0.4
                    let startX = -streakW + CGFloat(phase) * (size.width + streakW)
                    let y = size.height * streak.y
                    
                    // Fade in/out at edges
                    let opacity: Double
                    if phase < 0.15 {
                        opacity = phase / 0.15
                    } else if phase > 0.85 {
                        opacity = (1.0 - phase) / 0.15
                    } else {
                        opacity = 1.0
                    }
                    
                    let streakH = 1.2 * scale
                    let rect = CGRect(x: startX, y: y - streakH / 2, width: streakW, height: streakH)
                    let path = Capsule().path(in: rect)
                    context.fill(path, with: .color(.white.opacity(0.3 * opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Coordinator

struct WeatherEffectOverlay: View {
    let condition: AppWeatherCondition
    let isCompact: Bool
    let iconHeight: CGFloat
    
    init(condition: AppWeatherCondition, isCompact: Bool, iconHeight: CGFloat = 32) {
        self.condition = condition
        self.isCompact = isCompact
        self.iconHeight = iconHeight
    }
    
    var body: some View {
        switch condition {
        case .clear:
            SunGlowEffect()
        case .partlyCloudy:
            SunGlowEffect(subtle: true)
        case .cloudy:
            CloudDriftEffect()
        case .rain:
            RainDropsEffect(isHeavy: true, iconHeight: iconHeight)
                .frame(maxWidth: .infinity, alignment: .top)
        case .drizzle:
            RainDropsEffect(isHeavy: false, iconHeight: iconHeight)
                .frame(maxWidth: .infinity, alignment: .top)
        case .snow:
            SnowflakesEffect(iconHeight: iconHeight)
                .frame(maxWidth: .infinity, alignment: .top)
        case .wind:
            WindStreaksEffect()
        default:
            EmptyView()
        }
    }
}
#Preview("Weather Effects") {
    let conditions: [(String, String, AppWeatherCondition)] = [
        ("sun.max.fill", "Clear", .clear),
        ("cloud.sun.fill", "Partly Cloudy", .partlyCloudy),
        ("cloud.fill", "Cloudy", .cloudy),
        ("cloud.fill", "Rain", .rain),
        ("cloud.fill", "Drizzle", .drizzle),
        ("cloud.fill", "Snow", .snow),
        ("cloud.fog.fill", "Fog", .fog),
        ("wind", "Wind", .wind),
    ]
    
    VStack(spacing: 32) {
        ForEach(Array(conditions.enumerated()), id: \.offset) { _, item in
            HStack(spacing: 16) {
                Image(systemName: item.0)
                    .font(.system(size: 48))
                    .symbolRenderingMode(.multicolor)
                    .frame(width: 64, height: 64)
                    .background(alignment: .top) {
                        WeatherEffectOverlay(condition: item.2, isCompact: false, iconHeight: 64)
                    }
                Text(item.1)
                    .font(.title3)
                    .frame(width: 120, alignment: .leading)
            }
        }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
    .preferredColorScheme(.dark)
}

