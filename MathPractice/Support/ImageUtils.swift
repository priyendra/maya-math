import UIKit
import PencilKit

enum ImageUtils {
    /// Downscales so the long edge is at most `maxEdge` px and encodes as JPEG (what we send to Claude).
    static func jpegForAPI(_ data: Data, maxEdge: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(image, maxEdge: maxEdge, quality: quality)
    }

    static func jpeg(_ image: UIImage, maxEdge: CGFloat, quality: CGFloat = 0.85) -> Data? {
        let size = image.size
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    static func rotated90(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
        return out.jpegData(compressionQuality: 0.85)
    }

    static func uprightImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
    }

    /// Crops a region given as fractions of the image (x, y = top-left), with padding.
    static func crop(_ data: Data, x: Double, y: Double, width: Double, height: Double, padding: Double = 0.02) -> Data? {
        guard let image = UIImage(data: data), let cg = normalizedCGImage(image) else { return nil }
        let w = Double(cg.width), h = Double(cg.height)
        let x0 = max(0, x - padding), y0 = max(0, y - padding)
        let x1 = min(1, x + width + padding), y1 = min(1, y + height + padding)
        guard x1 > x0, y1 > y0 else { return nil }
        let rect = CGRect(x: x0 * w, y: y0 * h, width: (x1 - x0) * w, height: (y1 - y0) * h).integral
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.85)
    }

    /// Redraws the image so its pixel data is upright (scans/photos may carry an orientation flag).
    private static func normalizedCGImage(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }.cgImage
    }

    /// Renders handwriting on white, cropped to the ink with a margin, for grading.
    static func renderDrawing(_ drawing: PKDrawing, maxEdge: CGFloat = 2000) -> Data? {
        let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
        guard !drawing.strokes.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(2, maxEdge / max(bounds.width, bounds.height))
        let ink = drawing.image(from: bounds, scale: scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            // Force dark ink so dark-mode strokes are visible on white.
            ink.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: CGRect(origin: .zero, size: size))
        }
        return image.pngData()
    }
}
