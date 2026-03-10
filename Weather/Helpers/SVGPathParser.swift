//
//  SVGPathParser.swift
//  Weather
//
//  Parses the world.svg file and converts country paths to CGPaths.
//

import Foundation
import CoreGraphics

struct CountryPath: Identifiable {
    let id: String       // ISO country code e.g. "GB"
    let title: String    // e.g. "United Kingdom"
    let path: CGPath
}

// MARK: - SVG XML Parser

class SVGMapParser: NSObject, XMLParserDelegate {
    private var countries: [CountryPath] = []
    
    static func parse() -> [CountryPath] {
        guard let url = Bundle.main.url(forResource: "world", withExtension: "svg") else {
            return []
        }
        
        let parser = SVGMapParser()
        guard let xmlParser = XMLParser(contentsOf: url) else {
            return []
        }
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.countries
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "path",
           let id = attributeDict["id"],
           let title = attributeDict["title"],
           let d = attributeDict["d"] {
            if let cgPath = SVGPathDParser.parse(d) {
                countries.append(CountryPath(id: id, title: title, path: cgPath))
            }
        }
    }
}

// MARK: - SVG Path D-String Parser

enum SVGPathDParser {
    
    static func parse(_ d: String) -> CGPath? {
        let path = CGMutablePath()
        var scanner = PathScanner(d)
        var currentPoint = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControlPoint: CGPoint? = nil
        var lastCommand: Character = " "
        
        while let command = scanner.nextCommand() {
            switch command {
            case "M":
                if let pt = scanner.nextPoint() {
                    path.move(to: pt)
                    currentPoint = pt
                    subpathStart = pt
                    // Subsequent coordinate pairs are treated as implicit L
                    while let pt = scanner.nextPoint() {
                        path.addLine(to: pt)
                        currentPoint = pt
                    }
                }
                lastControlPoint = nil
                
            case "m":
                if let delta = scanner.nextPoint() {
                    let pt = CGPoint(x: currentPoint.x + delta.x, y: currentPoint.y + delta.y)
                    path.move(to: pt)
                    currentPoint = pt
                    subpathStart = pt
                    // Subsequent coordinate pairs are treated as implicit l
                    while let delta = scanner.nextPoint() {
                        let pt = CGPoint(x: currentPoint.x + delta.x, y: currentPoint.y + delta.y)
                        path.addLine(to: pt)
                        currentPoint = pt
                    }
                }
                lastControlPoint = nil
                
            case "L":
                while let pt = scanner.nextPoint() {
                    path.addLine(to: pt)
                    currentPoint = pt
                }
                lastControlPoint = nil
                
            case "l":
                while let delta = scanner.nextPoint() {
                    let pt = CGPoint(x: currentPoint.x + delta.x, y: currentPoint.y + delta.y)
                    path.addLine(to: pt)
                    currentPoint = pt
                }
                lastControlPoint = nil
                
            case "H":
                while let x = scanner.nextNumber() {
                    let pt = CGPoint(x: CGFloat(x), y: currentPoint.y)
                    path.addLine(to: pt)
                    currentPoint = pt
                }
                lastControlPoint = nil
                
            case "h":
                while let dx = scanner.nextNumber() {
                    let pt = CGPoint(x: currentPoint.x + CGFloat(dx), y: currentPoint.y)
                    path.addLine(to: pt)
                    currentPoint = pt
                }
                lastControlPoint = nil
                
            case "V":
                while let y = scanner.nextNumber() {
                    let pt = CGPoint(x: currentPoint.x, y: CGFloat(y))
                    path.addLine(to: pt)
                    currentPoint = pt
                }
                lastControlPoint = nil
                
            case "v":
                while let dy = scanner.nextNumber() {
                    let pt = CGPoint(x: currentPoint.x, y: currentPoint.y + CGFloat(dy))
                    path.addLine(to: pt)
                    currentPoint = pt
                }
                lastControlPoint = nil
                
            case "C":
                while let cp1 = scanner.nextPoint(),
                      let cp2 = scanner.nextPoint(),
                      let end = scanner.nextPoint() {
                    path.addCurve(to: end, control1: cp1, control2: cp2)
                    lastControlPoint = cp2
                    currentPoint = end
                }
                
            case "c":
                while let dcp1 = scanner.nextPoint(),
                      let dcp2 = scanner.nextPoint(),
                      let dend = scanner.nextPoint() {
                    let cp1 = CGPoint(x: currentPoint.x + dcp1.x, y: currentPoint.y + dcp1.y)
                    let cp2 = CGPoint(x: currentPoint.x + dcp2.x, y: currentPoint.y + dcp2.y)
                    let end = CGPoint(x: currentPoint.x + dend.x, y: currentPoint.y + dend.y)
                    path.addCurve(to: end, control1: cp1, control2: cp2)
                    lastControlPoint = cp2
                    currentPoint = end
                }
                
            case "S":
                while let cp2 = scanner.nextPoint(),
                      let end = scanner.nextPoint() {
                    let cp1: CGPoint
                    if lastCommand == "S" || lastCommand == "s" || lastCommand == "C" || lastCommand == "c",
                       let lcp = lastControlPoint {
                        cp1 = CGPoint(x: 2 * currentPoint.x - lcp.x, y: 2 * currentPoint.y - lcp.y)
                    } else {
                        cp1 = currentPoint
                    }
                    path.addCurve(to: end, control1: cp1, control2: cp2)
                    lastControlPoint = cp2
                    currentPoint = end
                }
                
            case "s":
                while let dcp2 = scanner.nextPoint(),
                      let dend = scanner.nextPoint() {
                    let cp1: CGPoint
                    if lastCommand == "S" || lastCommand == "s" || lastCommand == "C" || lastCommand == "c",
                       let lcp = lastControlPoint {
                        cp1 = CGPoint(x: 2 * currentPoint.x - lcp.x, y: 2 * currentPoint.y - lcp.y)
                    } else {
                        cp1 = currentPoint
                    }
                    let cp2 = CGPoint(x: currentPoint.x + dcp2.x, y: currentPoint.y + dcp2.y)
                    let end = CGPoint(x: currentPoint.x + dend.x, y: currentPoint.y + dend.y)
                    path.addCurve(to: end, control1: cp1, control2: cp2)
                    lastControlPoint = cp2
                    currentPoint = end
                }
                
            case "Q":
                while let cp = scanner.nextPoint(),
                      let end = scanner.nextPoint() {
                    path.addQuadCurve(to: end, control: cp)
                    lastControlPoint = cp
                    currentPoint = end
                }
                
            case "q":
                while let dcp = scanner.nextPoint(),
                      let dend = scanner.nextPoint() {
                    let cp = CGPoint(x: currentPoint.x + dcp.x, y: currentPoint.y + dcp.y)
                    let end = CGPoint(x: currentPoint.x + dend.x, y: currentPoint.y + dend.y)
                    path.addQuadCurve(to: end, control: cp)
                    lastControlPoint = cp
                    currentPoint = end
                }
                
            case "T":
                while let end = scanner.nextPoint() {
                    let cp: CGPoint
                    if lastCommand == "Q" || lastCommand == "q" || lastCommand == "T" || lastCommand == "t",
                       let lcp = lastControlPoint {
                        cp = CGPoint(x: 2 * currentPoint.x - lcp.x, y: 2 * currentPoint.y - lcp.y)
                    } else {
                        cp = currentPoint
                    }
                    path.addQuadCurve(to: end, control: cp)
                    lastControlPoint = cp
                    currentPoint = end
                }
                
            case "t":
                while let dend = scanner.nextPoint() {
                    let cp: CGPoint
                    if lastCommand == "Q" || lastCommand == "q" || lastCommand == "T" || lastCommand == "t",
                       let lcp = lastControlPoint {
                        cp = CGPoint(x: 2 * currentPoint.x - lcp.x, y: 2 * currentPoint.y - lcp.y)
                    } else {
                        cp = currentPoint
                    }
                    let end = CGPoint(x: currentPoint.x + dend.x, y: currentPoint.y + dend.y)
                    path.addQuadCurve(to: end, control: cp)
                    lastControlPoint = cp
                    currentPoint = end
                }
                
            case "Z", "z":
                path.closeSubpath()
                currentPoint = subpathStart
                lastControlPoint = nil
                
            default:
                break
            }
            
            lastCommand = command
        }
        
        return path.isEmpty ? nil : path
    }
}

// MARK: - Path Scanner

/// Tokenizer for SVG path d-strings.
/// Handles coordinate parsing with negative numbers, commas,
/// spaces, and scientific notation (e.g. 10e-4).
private struct PathScanner {
    private let chars: [Character]
    private var index: Int
    
    init(_ string: String) {
        self.chars = Array(string)
        self.index = 0
    }
    
    private static let commandChars: Set<Character> = [
        "M", "m", "L", "l", "H", "h", "V", "v",
        "C", "c", "S", "s", "Q", "q", "T", "t",
        "A", "a", "Z", "z"
    ]
    
    /// Advance past whitespace and commas
    private mutating func skipSeparators() {
        while index < chars.count {
            let c = chars[index]
            if c == " " || c == "\t" || c == "\n" || c == "\r" || c == "," {
                index += 1
            } else {
                break
            }
        }
    }
    
    /// Try to read the next command character
    mutating func nextCommand() -> Character? {
        skipSeparators()
        guard index < chars.count else { return nil }
        let c = chars[index]
        if Self.commandChars.contains(c) {
            index += 1
            return c
        }
        return nil
    }
    
    /// Try to read the next number (handles sign, decimal, scientific notation)
    mutating func nextNumber() -> Double? {
        skipSeparators()
        guard index < chars.count else { return nil }
        
        // Check if we're at a command character (not a number)
        let c = chars[index]
        if Self.commandChars.contains(c) {
            return nil
        }
        
        var numStr = ""
        
        // Optional sign
        if index < chars.count && (chars[index] == "-" || chars[index] == "+") {
            numStr.append(chars[index])
            index += 1
        }
        
        // Integer part
        var hasDigits = false
        while index < chars.count && chars[index].isNumber {
            numStr.append(chars[index])
            index += 1
            hasDigits = true
        }
        
        // Decimal part
        if index < chars.count && chars[index] == "." {
            numStr.append(".")
            index += 1
            while index < chars.count && chars[index].isNumber {
                numStr.append(chars[index])
                index += 1
                hasDigits = true
            }
        }
        
        guard hasDigits else { return nil }
        
        // Scientific notation (e.g., 10e-4)
        if index < chars.count && (chars[index] == "e" || chars[index] == "E") {
            numStr.append(chars[index])
            index += 1
            if index < chars.count && (chars[index] == "-" || chars[index] == "+") {
                numStr.append(chars[index])
                index += 1
            }
            while index < chars.count && chars[index].isNumber {
                numStr.append(chars[index])
                index += 1
            }
        }
        
        return Double(numStr)
    }
    
    /// Try to read the next coordinate pair as a CGPoint
    mutating func nextPoint() -> CGPoint? {
        guard let x = nextNumber() else { return nil }
        guard let y = nextNumber() else { return nil }
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }
}
