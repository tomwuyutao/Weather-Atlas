//
//  CountryBoundaryCatalog.swift
//  Weather
//
//  Loads lightweight Natural Earth country polygons for map preview masks.
//

import Foundation

struct CountryBoundaryFeature: Encodable, Equatable {
    let type: String
    let geometry: BoundaryGeometry
}

struct BoundaryGeometry: Encodable, Equatable {
    let type: String
    let coordinates: BoundaryCoordinates
}

enum BoundaryCoordinates: Encodable, Equatable {
    case polygon([[[Double]]])
    case multiPolygon([[[[Double]]]])

    fileprivate init(from geometry: DecodedBoundaryGeometry) throws {
        switch geometry.type {
        case "Polygon":
            self = .polygon(try geometry.coordinates.decode([[[Double]]].self))
        case "MultiPolygon":
            self = .multiPolygon(try geometry.coordinates.decode([[[[Double]]]].self))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported geometry type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .polygon(let coordinates):
            try coordinates.encode(to: encoder)
        case .multiPolygon(let coordinates):
            try coordinates.encode(to: encoder)
        }
    }
}

struct CountryBoundaryCatalog {
    static let shared = CountryBoundaryCatalog()

    private let featuresByISO3: [String: CountryBoundaryFeature]

    init() {
        featuresByISO3 = Self.loadFeatures()
    }

    func feature(for country: CountryCityGroup?) -> CountryBoundaryFeature? {
        guard let iso3 = country?.iso3.uppercased(), !iso3.isEmpty else { return nil }
        return featuresByISO3[iso3]
    }

    private static func loadFeatures() -> [String: CountryBoundaryFeature] {
        guard let url = Bundle.main.url(forResource: "country_boundaries", withExtension: "geojson")
            ?? Bundle.main.url(forResource: "country_boundaries", withExtension: "geojson", subdirectory: "Assets"),
              let data = try? Data(contentsOf: url),
              let collection = try? JSONDecoder().decode(DecodedBoundaryCollection.self, from: data) else {
            return [:]
        }

        var result: [String: CountryBoundaryFeature] = [:]
        for feature in collection.features {
            let iso3 = feature.properties.isoA3.uppercased()
            guard iso3 != "-99", !iso3.isEmpty,
                  let coordinates = try? BoundaryCoordinates(from: feature.geometry) else { continue }
            result[iso3] = CountryBoundaryFeature(
                type: "Feature",
                geometry: BoundaryGeometry(type: feature.geometry.type, coordinates: coordinates)
            )
        }
        return result
    }
}

private struct DecodedBoundaryCollection: Decodable {
    let features: [DecodedBoundaryFeature]
}

private struct DecodedBoundaryFeature: Decodable {
    let properties: DecodedBoundaryProperties
    let geometry: DecodedBoundaryGeometry
}

private struct DecodedBoundaryProperties: Decodable {
    let isoA3: String

    enum CodingKeys: String, CodingKey {
        case isoA3 = "ISO_A3"
    }
}

private struct DecodedBoundaryGeometry: Decodable {
    let type: String
    let coordinates: JSONValue
}

private enum JSONValue: Decodable {
    case array([JSONValue])
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        self = .array(try container.decode([JSONValue].self))
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(EncodableJSONValue(self))
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct EncodableJSONValue: Encodable {
    let value: JSONValue

    init(_ value: JSONValue) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        switch value {
        case .number(let number):
            var container = encoder.singleValueContainer()
            try container.encode(number)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(EncodableJSONValue(value))
            }
        }
    }
}
