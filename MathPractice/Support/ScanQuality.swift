import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Instant on-device check of a scanned page, so a shaky or hurried scan can be retaken while the book is still
/// open. Uses only CoreGraphics/Vision (no network). Claude's reading pass does the thorough check later.
enum ScanQuality {
    enum Issue: String, Codable, CaseIterable {
        // (Not checked here: text cut off at an edge — noisy on real scans, Claude catches it reliably — and "not a
        // book page" — sparse pages with big photos tripped it; Claude reports pages that aren't from the book.)
        case blurry, dark

        /// Short, kid-friendly advice.
        var advice: String {
            switch self {
            case .blurry: return "Blurry – hold the iPad still until it takes the picture."
            case .dark: return "Too dark – scan in a brighter spot."
            }
        }
    }

    struct Metrics: CustomStringConvertible {
        var sharpness: Double      // edge strength of text strokes, relative to page contrast
        var brightness: Double     // mean luminance 0…1
        var textLines: Int
        var pageNumber: Int?       // the printed page number, if found near the top or bottom
        var description: String {
            String(format: "sharp=%.3f bright=%.2f lines=%d page=%@", sharpness, brightness, textLines,
                   pageNumber.map(String.init) ?? "-")
        }
    }

    // Calibrated on two real chapters (138 scans) vs. blurred / darkened copies of them. Sharpness is measured only
    // inside text regions, so pages that are mostly photo or white space aren't mistaken for blurry.
    static let minSharpness = 0.22
    static let minBrightness = 0.6

    static func issues(_ m: Metrics) -> [Issue] {
        var out: [Issue] = []
        if m.sharpness < minSharpness { out.append(.blurry) }
        if m.brightness < minBrightness { out.append(.dark) }
        return out
    }

    static func check(_ image: CGImage) -> [Issue] { issues(measure(image)) }

    static func measure(_ image: CGImage) -> Metrics {
        let (gray, w, h) = grayscale(image, longEdge: 1200)
        var m = Metrics(sharpness: 0, brightness: 0, textLines: 0, pageNumber: nil)
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

        // Text regions (and the page number).
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let obs = request.results ?? []
        m.textLines = obs.count
        m.pageNumber = pageNumber(obs)

        // Mask: text boxes (padded). With no text found (e.g. heavy blur), use the whole page.
        var mask = [Bool](repeating: obs.isEmpty, count: w * h)
        for o in obs {
            let b = o.boundingBox   // normalized, origin bottom-left; buffer row 0 is the top
            let pad = 0.01
            let x0 = max(Int((b.minX - pad) * Double(w)), 1), x1 = min(Int((b.maxX + pad) * Double(w)), w - 2)
            let y0 = max(Int((1 - b.maxY - pad) * Double(h)), 1), y1 = min(Int((1 - b.minY + pad) * Double(h)), h - 2)
            guard x0 < x1, y0 < y1 else { continue }
            for y in y0...y1 { for x in x0...x1 { mask[y * w + x] = true } }
        }

        // Sharpness: strong Laplacian responses (text strokes) relative to contrast. Blur flattens them.
        var lap = [Int](repeating: 0, count: 1021)
        var count = 0
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) where mask[row + x] {
                let i = row + x
                let l = 4 * Int(gray[i]) - Int(gray[i - 1]) - Int(gray[i + 1]) - Int(gray[i - w]) - Int(gray[i + w])
                lap[min(abs(l), 1020)] += 1
                count += 1
            }
        }
        // Mean of the strongest 2% of responses within text.
        let top = max(count / 50, 1)
        var taken = 0, total = 0
        for v in stride(from: 1020, through: 0, by: -1) where taken < top {
            let n = min(lap[v], top - taken)
            taken += n
            total += n * v
        }
        m.sharpness = Double(total) / Double(taken) / contrast / 4
        return m
    }

    /// A standalone number (1–4 digits) near the top or bottom of the page: the printed page number.
    private static func pageNumber(_ obs: [VNRecognizedTextObservation]) -> Int? {
        var best: (Int, Double)?
        for o in obs {
            guard let text = o.topCandidates(1).first?.string else { continue }
            let b = o.boundingBox
            let nearEdge = b.minY < 0.1 || b.maxY > 0.9
            guard nearEdge else { continue }
            // "293", or "293 Chapter 5" / "Chapter 5 293": take a number at either end.
            let tokens = text.split(separator: " ")
            for t in [tokens.first, tokens.last].compactMap({ $0 }) {
                guard t.count <= 4, let n = Int(t), n > 0 else { continue }
                let edgeness = Double(min(b.minY, 1 - b.maxY))   // closer to the edge wins
                if best == nil || edgeness < best!.1 { best = (n, edgeness) }
            }
        }
        return best?.0
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
    let pageNumber: Int?

    /// Straightens, compresses and checks new pages off the main thread.
    static func process(_ images: [UIImage]) async -> [ScannedPage] {
        await Task.detached(priority: .userInitiated) {
            var out: [ScannedPage] = []
            for image in images {
                autoreleasepool {
                    let page = ImageUtils.uprightImage(image)
                    guard let jpeg = ImageUtils.jpeg(page, maxEdge: 2400, quality: 0.85),
                          let thumb = ImageUtils.jpeg(page, maxEdge: 400, quality: 0.7) else { return }
                    let m = UIImage(data: jpeg)?.cgImage.map(ScanQuality.measure)
                    out.append(ScannedPage(jpeg: jpeg, thumbnail: thumb, issues: m.map(ScanQuality.issues) ?? [],
                                           pageNumber: m?.pageNumber))
                }
            }
            return out
        }.value
    }
}
#endif
