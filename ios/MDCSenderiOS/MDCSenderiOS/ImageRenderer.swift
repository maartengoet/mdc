import UIKit

enum ImageRenderer {
    static func renderJPEG(image: UIImage, settings: DisplaySettings) throws -> Data {
        guard settings.imageFit != .original else {
            guard let data = image.jpegData(compressionQuality: 0.95) else {
                throw ImageRenderError.encodeFailed
            }
            return data
        }

        let canvasSize = CGSize(width: settings.canvasWidth, height: settings.canvasHeight)
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            throw ImageRenderError.emptyImage
        }

        let drawRect: CGRect
        switch settings.imageFit {
        case .contain:
            let scale = min(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
            let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            drawRect = CGRect(
                x: (canvasSize.width - size.width) * settings.cropX,
                y: (canvasSize.height - size.height) * settings.cropY,
                width: size.width,
                height: size.height
            )
        case .cover:
            let scale = max(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
            let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            drawRect = CGRect(
                x: -(size.width - canvasSize.width) * settings.cropX,
                y: -(size.height - canvasSize.height) * settings.cropY,
                width: size.width,
                height: size.height
            )
        case .stretch:
            drawRect = CGRect(origin: .zero, size: canvasSize)
        case .original:
            drawRect = CGRect(origin: .zero, size: sourceSize)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let output = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
            image.draw(in: drawRect)
        }

        guard let data = output.jpegData(compressionQuality: 0.95) else {
            throw ImageRenderError.encodeFailed
        }
        return data
    }
}

enum ImageRenderError: LocalizedError {
    case emptyImage
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .emptyImage:
            "Image has no pixels"
        case .encodeFailed:
            "Could not encode JPEG"
        }
    }
}
