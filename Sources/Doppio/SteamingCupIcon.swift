import AppKit

/// Menu bar icon: SF Symbols' filled steaming cup when active; when inactive, the same cup hollowed out
/// (so both share the exact silhouette) and without steam. The cup stays in place in both states.
enum SteamingCupIcon {
    private static let symbolName = "cup.and.heat.waves.fill"
    private static let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    /// Common integral canvas so both states line up and stay pixel-aligned.
    private static let size = NSSize(width: 19, height: 18)
    /// Heights in symbol coordinates at 14 pt: the cup ends at `cupTop`, the steam wisps start at `steamStart`.
    private static let cupTop: CGFloat = 11
    private static let steamStart: CGFloat = 12
    /// Whole-point offsets: lift the cup so the icon is centered, and lower the steam closer to the rim.
    private static let cupLift: CGFloat = 2
    private static let steamDrop: CGFloat = 1
    /// Outline width of the hollow cup, matching SF Symbols' medium weight at 14 pt.
    private static let outlineWidth: CGFloat = 1.4

    static func image(active: Bool) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Doppio")?
            .withSymbolConfiguration(configuration) else { return nil }
        let image = NSImage(size: size, flipped: false) { rect in
            // Integral origins: SF Symbols have fractional sizes and blur when drawn on half pixels.
            if active {
                draw(symbol, clipFrom: 0, to: cupTop, offsetY: cupLift)
                draw(symbol, clipFrom: steamStart, to: size.height, offsetY: cupLift - steamDrop)
            } else {
                let scale = NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 1
                if let hollow = hollowCup(symbol, scale: scale) {
                    NSGraphicsContext.current?.cgContext.draw(hollow, in: rect)
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Doppio"
        return image
    }

    /// Draws the horizontal slice `[from, to)` of the symbol (in symbol coordinates), shifted up by `offsetY`.
    private static func draw(_ symbol: NSImage, clipFrom from: CGFloat, to: CGFloat, offsetY: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: 0, y: from + offsetY, width: size.width, height: to - from).clip()
        symbol.draw(in: NSRect(x: 0, y: offsetY, width: symbol.size.width, height: symbol.size.height))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Renders the filled cup at `scale` and keeps only its outer band: mask minus its erosion.
    /// Thin parts (the handle) are narrower than the band, so they survive unchanged.
    private static func hollowCup(_ symbol: NSImage, scale: CGFloat) -> CGImage? {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let mask = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4, bitsPerPixel: 32
        ) else { return nil }
        mask.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: mask)
        draw(symbol, clipFrom: 0, to: cupTop, offsetY: cupLift)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = mask.bitmapData else { return nil }
        let grid = Grid(width: width, height: height)
        var alpha = (0..<(width * height)).map { CGFloat(data[$0 * 4 + 3]) / 255 }

        // The filled glyph has holes: the mouth (notched by the steam wisps), a thin seam under the
        // front lip, and the handle. Fill all of them except the handle's round opening to get the
        // clean outer silhouette. The seam can leak into the handle hole, so keep only its thick core.
        let lineWidth = outlineWidth * scale
        let holes = grid.holes(in: alpha.map { $0 > 0.5 })
        guard let handle = holes.max(by: { grid.centroidX(of: $0) < grid.centroidX(of: $1) }) else { return nil }
        let core = Set(grid.open(handle, by: max(1, Int((scale).rounded()))))
        let mouth = holes.filter { $0 != handle }.max { $0.count < $1.count }
        for hole in holes {
            for i in hole where !core.contains(i) { alpha[i] = 1 }
        }

        // Cup measurements, taken at the middle of the mouth where the handle isn't attached.
        let solid = alpha.map { $0 > 0.5 }
        let mouthBox = mouth.map { grid.bounds(of: $0) }
        let midRow = mouthBox.map { ($0.minY + $0.maxY) / 2 } ?? height / 2
        let rowStart = midRow * width
        let cupRow = solid[rowStart..<(rowStart + width)]
        let handleLeft = grid.bounds(of: handle).minX
        let left = cupRow.firstIndex(of: true).map { $0 - rowStart } ?? 0
        let right = cupRow[..<(rowStart + handleLeft)].lastIndex(of: true).map { $0 - rowStart } ?? width - 1
        let top = (solid.firstIndex(of: true) ?? 0) / width

        let inside = alpha.map { $0 > 0.5 ? CGFloat(1) : $0 * 2 }
        let radius = lineWidth
        let reach = Int(radius.rounded(.up))
        var offsets: [(Int, Int, CGFloat)] = []
        for dy in -reach...reach {
            for dx in -reach...reach {
                let distance = (CGFloat(dx * dx + dy * dy)).squareRoot()
                // Partial weight on the disk's edge keeps the inner contour anti-aliased.
                let weight = min(max(radius + 0.5 - distance, 0), 1)
                if weight > 0 { offsets.append((dx, dy, weight)) }
            }
        }

        var output = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let a = alpha[y * width + x]
                guard a > 0 else { continue }
                // Erosion: the pixel stays "inside" only if its whole neighborhood is inside.
                var eroded: CGFloat = 1
                for (dx, dy, weight) in offsets {
                    let nx = x + dx, ny = y + dy
                    let neighbor = (nx < 0 || ny < 0 || nx >= width || ny >= height) ? 0 : inside[ny * width + nx]
                    eroded = min(eroded, 1 - weight * (1 - neighbor))
                }
                let value = UInt8((a * (1 - eroded) * 255).rounded())
                output[(y * width + x) * 4 + 3] = value
            }
        }
        // Where the handle joins the cup, the filled glyph has no wall (cup and handle are one blob),
        // so hollowing loses it. The cup body is symmetric: mirror the left half onto the right.
        for y in 0..<height {
            for x in left..<((left + right + 1) / 2) {
                let mirrored = left + right - x
                let from = (y * width + x) * 4 + 3, to = (y * width + mirrored) * 4 + 3
                output[to] = max(output[to], output[from])
            }
        }

        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let band = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { return nil }
        guard let mouth else { return band }

        // Redraw the mouth as an ellipse centered on the silhouette's band: the back on the cup's
        // top edge, the sides on the walls, the front on the lip (the bottom of the mouth hole).
        // Pixel rows run top-down here; CGContext is y-up.
        let lipRow = grid.bounds(of: mouth).maxY + 1
        let ellipse = CGRect(
            x: CGFloat(left) + lineWidth / 2,
            y: CGFloat(height - lipRow) - lineWidth / 2,
            width: CGFloat(right + 1 - left) - lineWidth,
            height: CGFloat(lipRow - top)
        )
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return band }
        context.draw(band, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(lineWidth)
        context.strokeEllipse(in: ellipse)
        return context.makeImage()
    }
}

/// Region helpers on a small pixel grid (row-major).
private struct Grid {
    let width: Int
    let height: Int

    private func neighbors(_ i: Int) -> [Int] {
        let x = i % width, y = i / width
        var result: [Int] = []
        if x > 0 { result.append(i - 1) }
        if x < width - 1 { result.append(i + 1) }
        if y > 0 { result.append(i - width) }
        if y < height - 1 { result.append(i + width) }
        return result
    }

    /// Bounding box (inclusive pixel indices) of a list of pixel indices.
    func bounds(of pixels: [Int]) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
        let xs = pixels.map { $0 % width }, ys = pixels.map { $0 / width }
        return (xs.min() ?? 0, xs.max() ?? 0, ys.min() ?? 0, ys.max() ?? 0)
    }

    func centroidX(of pixels: [Int]) -> Double {
        Double(pixels.reduce(0) { $0 + $1 % width }) / Double(max(pixels.count, 1))
    }

    /// Morphological opening (erode then dilate) of a pixel list by a disk of radius `r`.
    func open(_ pixels: [Int], by r: Int) -> [Int] {
        var set = [Bool](repeating: false, count: width * height)
        for i in pixels { set[i] = true }
        let eroded = morph(set, by: r, any: false)
        let opened = morph(eroded, by: r, any: true)
        return pixels.filter { opened[$0] }
    }

    private func morph(_ set: [Bool], by r: Int, any: Bool) -> [Bool] {
        var out = [Bool](repeating: false, count: set.count)
        for y in 0..<height {
            for x in 0..<width {
                var hit = !any
                search: for dy in -r...r {
                    for dx in -r...r where dx * dx + dy * dy <= r * r {
                        let nx = x + dx, ny = y + dy
                        let value = nx >= 0 && ny >= 0 && nx < width && ny < height && set[ny * width + nx]
                        if any && value { hit = true; break search }
                        if !any && !value { hit = false; break search }
                    }
                }
                out[y * width + x] = hit
            }
        }
        return out
    }

    /// Transparent regions not connected to the canvas border, as lists of pixel indices.
    func holes(in solid: [Bool]) -> [[Int]] {
        var visited = [Bool](repeating: false, count: solid.count)
        var result: [[Int]] = []
        for start in solid.indices where !solid[start] && !visited[start] {
            var stack = [start], region: [Int] = [], touchesBorder = false
            visited[start] = true
            while let i = stack.popLast() {
                region.append(i)
                let x = i % width, y = i / width
                if x == 0 || y == 0 || x == width - 1 || y == height - 1 { touchesBorder = true }
                for n in neighbors(i) where !solid[n] && !visited[n] {
                    visited[n] = true
                    stack.append(n)
                }
            }
            if !touchesBorder { result.append(region) }
        }
        return result
    }
}
