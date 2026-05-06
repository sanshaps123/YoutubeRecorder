import Vision
import CoreImage
import CoreVideo
import AppKit

// MARK: - Background Mode Enum

enum WebcamBackground: String, CaseIterable, Identifiable {
    case none = "None"
    case blur = "Blur"
    case sunset = "Sunset"
    case ocean = "Ocean"
    case forest = "Forest"
    case nightSky = "Night Sky"
    case warmStudio = "Studio"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none:       return "person.fill"
        case .blur:       return "camera.filters"
        case .sunset:     return "sun.horizon.fill"
        case .ocean:      return "water.waves"
        case .forest:     return "leaf.fill"
        case .nightSky:   return "moon.stars.fill"
        case .warmStudio: return "lightbulb.fill"
        }
    }

    var previewColors: (NSColor, NSColor) {
        switch self {
        case .none:       return (.clear, .clear)
        case .blur:       return (.gray, .darkGray)
        case .sunset:     return (NSColor(red: 1.0, green: 0.4, blue: 0.2, alpha: 1),
                                  NSColor(red: 0.8, green: 0.2, blue: 0.6, alpha: 1))
        case .ocean:      return (NSColor(red: 0.0, green: 0.4, blue: 0.8, alpha: 1),
                                  NSColor(red: 0.0, green: 0.75, blue: 0.7, alpha: 1))
        case .forest:     return (NSColor(red: 0.05, green: 0.35, blue: 0.15, alpha: 1),
                                  NSColor(red: 0.2, green: 0.65, blue: 0.35, alpha: 1))
        case .nightSky:   return (NSColor(red: 0.03, green: 0.03, blue: 0.15, alpha: 1),
                                  NSColor(red: 0.2, green: 0.08, blue: 0.35, alpha: 1))
        case .warmStudio: return (NSColor(red: 0.85, green: 0.65, blue: 0.45, alpha: 1),
                                  NSColor(red: 0.55, green: 0.35, blue: 0.25, alpha: 1))
        }
    }

    func ciGradientColors() -> (CIColor, CIColor)? {
        switch self {
        case .none, .blur: return nil
        case .sunset:     return (CIColor(red: 1.0, green: 0.4, blue: 0.2),
                                  CIColor(red: 0.8, green: 0.2, blue: 0.6))
        case .ocean:      return (CIColor(red: 0.0, green: 0.4, blue: 0.8),
                                  CIColor(red: 0.0, green: 0.75, blue: 0.7))
        case .forest:     return (CIColor(red: 0.05, green: 0.35, blue: 0.15),
                                  CIColor(red: 0.2, green: 0.65, blue: 0.35))
        case .nightSky:   return (CIColor(red: 0.03, green: 0.03, blue: 0.15),
                                  CIColor(red: 0.2, green: 0.08, blue: 0.35))
        case .warmStudio: return (CIColor(red: 0.85, green: 0.65, blue: 0.45),
                                  CIColor(red: 0.55, green: 0.35, blue: 0.25))
        }
    }
}

// MARK: - Background Processor (Vision Person Segmentation)

final class BackgroundProcessor: @unchecked Sendable {

    private let ciContext: CIContext
    private let segmentationRequest: VNGeneratePersonSegmentationRequest
    private var bufferPool: CVPixelBufferPool?
    private let lock = NSLock()
    private var _mode: WebcamBackground = .none

    var mode: WebcamBackground {
        get { lock.withLock { _mode } }
        set { lock.withLock { _mode = newValue } }
    }

    init() {
        ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
        segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .balanced
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func process(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        let currentMode = mode
        guard currentMode != .none else { return pixelBuffer }

        // Run person segmentation
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([segmentationRequest])
        } catch {
            return pixelBuffer
        }

        guard let observation = segmentationRequest.results?.first else { return pixelBuffer }
        let maskBuffer = observation.pixelBuffer

        let original = CIImage(cvPixelBuffer: pixelBuffer)
        let rawMask = CIImage(cvPixelBuffer: maskBuffer)

        // Scale mask to match original image dimensions
        let scaleX = original.extent.width / rawMask.extent.width
        let scaleY = original.extent.height / rawMask.extent.height
        let scaledMask = rawMask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Build background
        let background: CIImage
        switch currentMode {
        case .none:
            return pixelBuffer
        case .blur:
            background = original
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 18)
                .cropped(to: original.extent)
        default:
            guard let (c0, c1) = currentMode.ciGradientColors() else { return pixelBuffer }
            guard let gradient = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: original.extent.width, y: original.extent.height),
                "inputColor0": c0,
                "inputColor1": c1
            ])?.outputImage else { return pixelBuffer }
            background = gradient.cropped(to: original.extent)
        }

        // Composite: person (from mask) over background
        let composited = original.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: scaledMask
        ])

        // Render to output buffer
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        guard let pool = getPool(width: w, height: h) else { return pixelBuffer }

        var outBuf: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outBuf)
        guard let output = outBuf else { return pixelBuffer }

        ciContext.render(composited, to: output)
        return output
    }

    private func getPool(width: Int, height: Int) -> CVPixelBufferPool? {
        if let pool = bufferPool { return pool }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        bufferPool = pool
        return pool
    }
}
