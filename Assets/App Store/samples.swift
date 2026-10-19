#!/usr/bin/env swift

import AppKit

// Renders the sample SVGs in Samples/ for one language and writes them, with
// a manifest the app's screenshot seeder reads, into the given directory.
// Usage: ./samples.swift <en|ja> <output directory>

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
guard CommandLine.arguments.count == 3, ["en", "ja"].contains(CommandLine.arguments[1]) else {
    print("usage: samples.swift <en|ja> <output directory>")
    exit(1)
}
let language = CommandLine.arguments[1]
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// Text in the SVGs is written as ⟦English|日本語⟧.
func localized(_ svg: String) -> String {
    guard let pattern = try? NSRegularExpression(pattern: "⟦([^|⟧]*)\\|([^⟧]*)⟧") else { return svg }
    let template = language == "ja" ? "$2" : "$1"
    return pattern.stringByReplacingMatches(
        in: svg, range: NSRange(svg.startIndex..., in: svg), withTemplate: template
    )
}

/// `name~copy` is the same picture saved again smaller, and `name~crop` is a
/// tighter crop, so the duplicate scanner has something to find.
func render(_ name: String) -> Data? {
    let parts = name.split(separator: "~").map(String.init)
    let svgURL = scriptDir.appendingPathComponent("Samples/\(parts[0]).svg")
    guard let svg = try? String(contentsOf: svgURL, encoding: .utf8),
          let image = NSImage(data: Data(localized(svg).utf8)) else {
        print("could not read \(svgURL.path)")
        return nil
    }
    let variant = parts.count > 1 ? parts[1] : nil
    let scale: CGFloat = variant == "copy" ? 0.6 : 1.0
    var source = NSRect(origin: .zero, size: image.size)
    if variant == "crop" {
        source = source.insetBy(dx: image.size.width * 0.04, dy: image.size.height * 0.04)
    }
    let width = Int(source.width * scale), height = Int(source.height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: source,
               operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
}

let manifestURL = scriptDir.appendingPathComponent("samples.json")
guard let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] else {
    print("samples.json is not an object")
    exit(1)
}

var rendered: Set<String> = []
var allOK = true

func resolve(_ value: Any) -> Any {
    if let dictionary = value as? [String: Any] {
        if let name = dictionary[language] as? String, dictionary.keys.allSatisfy({ ["en", "ja"].contains($0) }) {
            return name
        }
        return dictionary.mapValues(resolve)
    }
    if let array = value as? [Any] {
        return array.map(resolve)
    }
    return value
}

func renderPics(in value: Any) {
    if let dictionary = value as? [String: Any] {
        for (key, child) in dictionary {
            if key == "pics" || key == "cover", let names = child as? [String] {
                for name in names where !rendered.contains(name) {
                    rendered.insert(name)
                    guard let data = render(name),
                          (try? data.write(to: outDir.appendingPathComponent("\(name).jpg"))) != nil else {
                        allOK = false
                        continue
                    }
                }
            } else {
                renderPics(in: child)
            }
        }
    } else if let array = value as? [Any] {
        array.forEach(renderPics)
    }
}

let resolved = resolve(manifest)
renderPics(in: resolved)
let json = try JSONSerialization.data(withJSONObject: resolved, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("manifest.json"))
print(outDir.path)
exit(allOK ? 0 : 1)
