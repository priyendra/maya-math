import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Instant on-device check of a scanned page, so a shaky or hurried scan can be retaken while the book is still
/// open. Uses only CoreGraphics/Vision (no network). Claude's reading pass does the thorough check later.
enum ScanQuality {
    enum Issue: String, Codable, CaseIterable {
        // (Text cut off at an edge isn't checked here: on real scans it mostly flagged harmless clipped footers or the
        // next page peeking in, and missed cuts through blank margins. Claude's reading pass catches it reliably.)
        case blurry, dark, noText

        /// Short, kid-friendly advice.
        var advice: String {
            switch self {
            case .blurry: return "Blurry – hold the iPad still until it takes the picture."
            case .dark: return "Too dark – scan in a brighter spot."
            case .noText: return "This doesn't look like a book page – check it's the right page."
            }
        }
    }

    struct Metrics: CustomStringConvertible {
        var sharpness: Double      // edge strength of text strokes, relative to page contrast
        var brightness: Double     // mean luminance 0…1
        var textLines: Int
        var edgeTextSides: [String] // image edges that at least two lines of text run into
        var description: String {
            String(format: "sharp=%.3f bright=%.2f lines=%d edges=%@", sharpness, brightness, textLines,
                   edgeTextSides.joined(separator: ","))
        }
    }

    // Calibrated on real textbook scans vs. blurred / darkened / cropped copies of them: sharp pages measure
    // 0.39–0.53, a slight blur 0.09–0.18, heavy or motion blur 0.02–0.15. Real pages are ≥ 0.9 bright.
    static let minSharpness = 0.25
    static let minBrightness = 0.6

    static func issues(_ m: Metrics) -> [Issue] {
        if m.sharpness < minSharpness { return [.blurry] }          // heavy blur also hides all text: say blurry
        if m.textLines < 3 { return [.noText] }
        var out: [Issue] = []
        if m.brightness < minBrightness { out.append(.dark) }
        return out
    }

    static func check(_ image: CGImage) -> [Issue] { issues(measure(image)) }

    static func measure(_ image: CGImage) -> Metrics {
        let (gray, w, h) = grayscale(image, longEdge: 1200)
        var m = Metrics(sharpness: 0, brightness: 0, textLines: 0, edgeTextSides: [])
        guard w > 2, h > 2 else { return m }

        // Brightness and contrast.
        var hist = [Int](repeating: 0, count: 256)
        var sum = 0
        for v in gray { hist[Int(v)] += 1; sum += Int(v) }
        m.brightness = Double(sum) / Double(gray.count) / 255
        func percentile(_ p: Double) -> Double {
            let target = Int(Double(gray.count) * p)
            var acc = 0
            for (i, c) in hist.enumerated() { acc += c; if acc >= target { return Double(i) } }
            return 255
        }
        let contrast = max(percentile(0.95) - percentile(0.02), 1)

        // Sharpness: strong Laplacian responses (text strokes) relative to contrast. Blur flattens them.
        var lap = [Int](repeating: 0, count: 1021)
        var count = 0
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let i = row + x
                let l = 4 * Int(gray[i]) - Int(gray[i - 1]) - Int(gray[i + 1]) - Int(gray[i - w]) - Int(gray[i + w])
                lap[min(abs(l), 1020)] += 1
                count += 1
            }
        }
        // Mean of the strongest 0.5% of responses.
        let top = max(count / 200, 1)
        var taken = 0, total = 0
        for v in stride(from: 1020, through: 0, by: -1) where taken < top {
            let n = min(lap[v], top - taken)
            taken += n
            total += n * v
        }
        m.sharpness = Double(total) / Double(taken) / contrast / 4

        // Text: how much, how confidently read, and whether it runs into an edge of the image.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let obs = request.results ?? []
        m.textLines = obs.count
        // A single clipped line is usually just the running footer/header; two or more means content is cut off.
        let margin = 0.006
        var touches: [String: Int] = [:]
        for o in obs where o.boundingBox.height > 0.008 {
            let b = o.boundingBox   // normalized, origin bottom-left
            if b.minX < margin { touches["left", default: 0] += 1 }
            if b.maxX > 1 - margin { touches["right", default: 0] += 1 }
            if b.minY < margin { touches["bottom", default: 0] += 1 }
            if b.maxY > 1 - margin { touches["top", default: 0] += 1 }
        }
        m.edgeTextSides = touches.filter { $0.value >= 2 }.keys.sorted()
        return m
    }

    private static func grayscale(_ image: CGImage, longEdge: Int) -> ([UInt8], Int, Int) {
        let scale = min(1, Double(longEdge) / Double(max(image.width, image.height)))
        let w = max(Int(Double(image.width) * scale), 1), h = max(Int(Double(image.height) * scale), 1)
        var px = [UInt8](repeating: 0, count: w * h)
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (px, w, h)
    }
}

#if canImport(UIKit)
import UIKit

/// A freshly scanned page, compressed for storage and checked on the iPad.
struct ScannedPage: Sendable {
    let jpeg: Data
    let thumbnail: Data
    let issues: [ScanQuality.Issue]

    /// Straightens, compresses and checks new pages off the main thread.
    static func process(_ images: [UIImage]) async -> [ScannedPage] {
        await Task.detached(priority: .userInitiated) {
            var out: [ScannedPage] = []
            for image in images {
                autoreleasepool {
                    let page = ImageUtils.uprightImage(image)
                    guard let jpeg = ImageUtils.jpeg(page, maxEdge: 2400, quality: 0.85),
                          let thumb = ImageUtils.jpeg(page, maxEdge: 400, quality: 0.7) else { return }
                    let issues = UIImage(data: jpeg)?.cgImage.map(ScanQuality.check) ?? []
                    out.append(ScannedPage(jpeg: jpeg, thumbnail: thumb, issues: issues))
                }
            }
            return out
        }.value
    }
}
#endif
