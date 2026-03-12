import SwiftUI
import MapKit

// MARK: - Map Thumbnail View

/// A small static illustration of a map mode, cropped to the British Isles region.
struct MapThumbnailView: View {
    let mode: String   // "minimal", "borders", "detailed"

    @Environment(\.appTheme) private var theme

    // UK bounding box in geographic coords (with padding)
    private static let ukMinLon: Double = -10.5
    private static let ukMaxLon: Double =   3.5
    private static let ukMinLat: Double =  48.5
    private static let ukMaxLat: Double =  61.5

    // Countries to show in the thumbnail
    private static let visibleIDs: Set<String> = ["GB", "IE", "FR", "BE", "NL", "DE", "DK", "NO"]

    // Shared parsed paths (loaded once)
    private static let allPaths: [CountryPath] = SVGMapParser.parse()

    private var paths: [CountryPath] {
        Self.allPaths.filter { Self.visibleIDs.contains($0.id) }
    }

    // SVG-space bounding box for the UK region
    private var svgCrop: CGRect {
        let tl = GeoProjection.geoToSVG(latitude: Self.ukMaxLat, longitude: Self.ukMinLon)
        let br = GeoProjection.geoToSVG(latitude: Self.ukMinLat, longitude: Self.ukMaxLon)
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }

    var body: some View {
        if mode == "detailed" {
            detailedThumbnail
        } else {
            svgThumbnail
        }
    }

    // MARK: - SVG Canvas Thumbnail (minimal / borders)

    private var svgThumbnail: some View {
        Canvas { context, size in
            let colors = AppTheme.shared.colors
            let crop = svgCrop
            guard crop.width > 0, crop.height > 0 else { return }

            // Uniform scale to fit crop inside canvas (preserve aspect ratio)
            let scale = min(size.width / crop.width, size.height / crop.height)

            // Center the scaled crop in the canvas
            let scaledW = crop.width * scale
            let scaledH = crop.height * scale
            let offsetX = (size.width - scaledW) / 2
            let offsetY = (size.height - scaledH) / 2

            // Matrix: translate crop origin to (0,0), scale uniformly, then offset to center
            let transform = CGAffineTransform(
                a: scale, b: 0,
                c: 0,     d: scale,
                tx: -crop.minX * scale + offsetX,
                ty: -crop.minY * scale + offsetY
            )

            // Boost contrast for thumbnail: push ocean darker, land brighter
            let ocean = colors.mapOcean.mix(with: .black, by: 0.10)
            let land  = colors.mapLand.mix(with: .white, by: 0.10)

            // 1. Ocean background
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ocean))

            let isBorders = mode == "borders"
            let landColor = land
            let mutedLand = ocean.mix(with: land, by: 0.55)
            let borderColor = colors.mapBorder

            // 2. Fill countries
            for country in paths {
                var t = transform
                guard let transformed = country.path.copy(using: &t) else { continue }
                let p = Path(transformed)
                if isBorders {
                    let fill = country.id == "GB" || country.id == "IE" ? landColor : mutedLand
                    context.fill(p, with: .color(fill))
                } else {
                    context.fill(p, with: .color(landColor))
                }
            }

            // 3. Borders (borders mode only)
            if isBorders {
                for country in paths {
                    var t = transform
                    guard let transformed = country.path.copy(using: &t) else { continue }
                    let isHighlighted = country.id == "GB" || country.id == "IE"
                    let color = isHighlighted
                        ? borderColor.mix(with: .white, by: 0.15)
                        : borderColor.opacity(0.5)
                    context.stroke(Path(transformed), with: .color(color), lineWidth: isHighlighted ? 1.6 : 1.0)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - MapKit Thumbnail (detailed)

    private var detailedThumbnail: some View {
        // The SVG crop spans ~15° lat × 14° lon centred on the British Isles.
        // Use the same centre; set longitudeDelta to drive the zoom and let MapKit
        // fill the height — this matches the SVG view better than latitudeDelta.
        let centerLat = (Self.ukMinLat + Self.ukMaxLat) / 2  // ~55.0
        let centerLon = (Self.ukMinLon + Self.ukMaxLon) / 2  // ~-3.5
        let spanLon   = (Self.ukMaxLon - Self.ukMinLon) * 1.8  // zoom out 40%

        return GeometryReader { geo in
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
                span: MKCoordinateSpan(latitudeDelta: spanLon * geo.size.height / geo.size.width,
                                       longitudeDelta: spanLon)
            ))) {
            }
            .mapStyle(.standard(emphasis: .muted))
            .mapControls { }
            .disabled(true)
            .allowsHitTesting(false)
            // Expand beyond bounds on all sides to push legal text out of view
            .frame(width: geo.size.width + 40, height: geo.size.height + 40)
            .offset(x: -22, y: -15)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
