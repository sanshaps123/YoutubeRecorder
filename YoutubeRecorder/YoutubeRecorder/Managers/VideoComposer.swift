import AVFoundation
import CoreImage
import CoreVideo
import CoreText
import AppKit

// MARK: - Click Highlight Data

struct ClickHighlight: Sendable {
    let position: CGPoint      // Normalized (0-1) screen position
    let timestamp: CFTimeInterval
    let duration: Double = 0.6
}

// MARK: - Keystroke Data

struct KeystrokeDisplay: Sendable {
    let text: String           // e.g. "⌘C"
    let timestamp: CFTimeInterval
    let duration: Double = 2.0
}

final class VideoComposer: @unchecked Sendable {

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?

    private let ciContext: CIContext
    private var isSessionStarted = false
    private var outputPool: CVPixelBufferPool?

    // Thread-safe overlay config
    private let configLock = NSLock()
    private var _webcamEnabled = true
    private var _webcamNormalizedCenter = CGPoint(x: 0.82, y: 0.82)
    private var _webcamDiameter: CGFloat = 200

    // Pause support
    private var _isPaused = false
    private var pauseStartTime: CMTime = .invalid
    private var totalPauseOffset: CMTime = .zero

    // Click highlights
    private var _clickHighlights: [ClickHighlight] = []

    // Keystroke display
    private var _currentKeystroke: KeystrokeDisplay?

    // Caption display
    private var _currentCaptionText: String = ""
    private var _captionStyle: CaptionStyle = .default
    private var _captionEnabled = false

    // Click highlighting enabled
    private var _clickHighlightEnabled = false
    private var _keystrokeDisplayEnabled = false
    
    // MARK: - Caption State (ADD THIS INSIDE VideoComposer)

    private var captionState = CaptionState()
    private var lastCaptionText: String = ""

    // Recording mode (screen only, screen+webcam, camera only)
    private var _recordingMode: RecordingMode = .screenAndWebcam

    // Webcam shape
    private var _webcamShape: WebcamShape = .circle

    var webcamEnabled: Bool {
        get { configLock.withLock { _webcamEnabled } }
        set { configLock.withLock { _webcamEnabled = newValue } }
    }
    var webcamNormalizedCenter: CGPoint {
        get { configLock.withLock { _webcamNormalizedCenter } }
        set { configLock.withLock { _webcamNormalizedCenter = newValue } }
    }
    var webcamDiameter: CGFloat {
        get { configLock.withLock { _webcamDiameter } }
        set { configLock.withLock { _webcamDiameter = newValue } }
    }

    var isPaused: Bool {
        get { configLock.withLock { _isPaused } }
        set {
            configLock.withLock {
                if newValue && !_isPaused {
                    // Entering pause: record when we paused
                    // pauseStartTime will be set on next frame
                    _isPaused = true
                } else if !newValue && _isPaused {
                    // Resuming: pauseStartTime → now offset will be computed on next frame
                    _isPaused = false
                }
            }
        }
    }

    var clickHighlightEnabled: Bool {
        get { configLock.withLock { _clickHighlightEnabled } }
        set { configLock.withLock { _clickHighlightEnabled = newValue } }
    }

    var keystrokeDisplayEnabled: Bool {
        get { configLock.withLock { _keystrokeDisplayEnabled } }
        set { configLock.withLock { _keystrokeDisplayEnabled = newValue } }
    }

    var recordingMode: RecordingMode {
        get { configLock.withLock { _recordingMode } }
        set { configLock.withLock { _recordingMode = newValue } }
    }

    var webcamShape: WebcamShape {
        get { configLock.withLock { _webcamShape } }
        set { configLock.withLock { _webcamShape = newValue } }
    }

    func addClickHighlight(_ highlight: ClickHighlight) {
        configLock.withLock { _clickHighlights.append(highlight) }
    }

    func setCurrentKeystroke(_ keystroke: KeystrokeDisplay?) {
        configLock.withLock { _currentKeystroke = keystroke }
    }

    var captionEnabled: Bool {
        get { configLock.withLock { _captionEnabled } }
        set { configLock.withLock { _captionEnabled = newValue } }
    }

    var captionStyle: CaptionStyle {
        get { configLock.withLock { _captionStyle } }
        set { configLock.withLock { _captionStyle = newValue } }
    }

    func setCurrentCaption(_ text: String) {
        configLock.withLock { _currentCaptionText = text }
    }

    var getCameraFrame: (() -> CVPixelBuffer?)?

    init() {
        ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])
    }

    // MARK: - Lifecycle

    func startWriting(to url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 6,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true

        let adaptorAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let pbAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: vInput,
            sourcePixelBufferAttributes: adaptorAttrs
        )

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        aInput.expectsMediaDataInRealTime = true

        if writer.canAdd(vInput) { writer.add(vInput) }
        if writer.canAdd(aInput) { writer.add(aInput) }

        self.assetWriter = writer
        self.videoInput = vInput
        self.audioInput = aInput
        self.adaptor = pbAdaptor
        self.isSessionStarted = false
        self.outputPool = nil
        self.totalPauseOffset = .zero
        self.pauseStartTime = .invalid

        // Reset pause/highlight state
        configLock.withLock {
            _isPaused = false
            _clickHighlights = []
            _currentKeystroke = nil
        }
    }

    func appendScreenFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = assetWriter else { return }
        guard writer.status == .unknown || writer.status == .writing else { return }
        guard let videoInput, let adaptor else { return }

        // Skip frames while paused
        let paused = isPaused
        let rawPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if paused {
            // Record when pause started (on first paused frame)
            if pauseStartTime == .invalid {
                pauseStartTime = rawPTS
            }
            return // Don't write frames while paused
        }

        // If we just resumed from pause, compute the offset
        if pauseStartTime != .invalid {
            let pauseDuration = CMTimeSubtract(rawPTS, pauseStartTime)
            totalPauseOffset = CMTimeAdd(totalPauseOffset, pauseDuration)
            pauseStartTime = .invalid
        }

        let pts = CMTimeSubtract(rawPTS, totalPauseOffset)

        if !isSessionStarted {
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            isSessionStarted = true
        }

        guard videoInput.isReadyForMoreMediaData else { return }
        guard let screenPB = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var result: CVPixelBuffer = screenPB
        let mode = recordingMode
        let w = CVPixelBufferGetWidth(screenPB)
        let h = CVPixelBufferGetHeight(screenPB)

        switch mode {
        case .screenOnly:
            // Just screen, no webcam
            break
        case .screenAndWebcam:
            // Screen + circular webcam overlay
            if webcamEnabled, let cameraPB = getCameraFrame?() {
                result = compositeFrames(screen: screenPB, camera: cameraPB) ?? screenPB
            }
        case .cameraOnly:
            // Full-frame camera (ignore screen)
            if let cameraPB = getCameraFrame?() {
                result = renderFullCamera(camera: cameraPB, outputWidth: w, outputHeight: h) ?? screenPB
            }
        }

        // Click highlight rendering
        let (highlights, clickEnabled) = configLock.withLock {
            (_clickHighlights, _clickHighlightEnabled)
        }
        if clickEnabled && !highlights.isEmpty {
            result = renderClickHighlights(on: result, highlights: highlights) ?? result
        }

        // Keystroke rendering
        let (keystroke, keyEnabled) = configLock.withLock {
            (_currentKeystroke, _keystrokeDisplayEnabled)
        }
        if keyEnabled, let ks = keystroke {
            result = renderKeystroke(on: result, keystroke: ks) ?? result
        }

        // Caption rendering (burned into video)
        let (captionText, capStyle, capEnabled) = configLock.withLock {
            (_currentCaptionText, _captionStyle, _captionEnabled)
        }
        if capEnabled && !captionText.isEmpty {
            result = renderCaption(on: result, text: captionText, style: capStyle) ?? result
        }

        adaptor.append(result, withPresentationTime: pts)
    }

    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        guard !isPaused else { return }
        guard let writer = assetWriter, writer.status == .writing, isSessionStarted else { return }
        guard let audioInput, audioInput.isReadyForMoreMediaData else { return }

        // Offset the audio PTS to match video
        if totalPauseOffset != .zero {
            let rawPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let adjustedPTS = CMTimeSubtract(rawPTS, totalPauseOffset)
            // For audio we just check it's valid and append as-is since
            // AVAssetWriter handles audio timing relative to session start
            if adjustedPTS.value < 0 { return }
        }

        audioInput.append(sampleBuffer)
    }

    func finishWriting() async -> URL? {
        guard let writer = assetWriter, writer.status == .writing else { return nil }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()
        let url = writer.outputURL
        cleanup()
        return writer.status == .completed ? url : nil
    }

    private func cleanup() {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        adaptor = nil
        isSessionStarted = false
        outputPool = nil
        totalPauseOffset = .zero
        pauseStartTime = .invalid
    }

    // MARK: - Core Image Compositing

    private func compositeFrames(screen: CVPixelBuffer, camera: CVPixelBuffer) -> CVPixelBuffer? {
        let w = CGFloat(CVPixelBufferGetWidth(screen))
        let h = CGFloat(CVPixelBufferGetHeight(screen))

        let screenImg = CIImage(cvPixelBuffer: screen)
        var camImg = CIImage(cvPixelBuffer: camera)
        let currentShape = webcamShape

        // Scale webcam to desired diameter (retina-aware)
        let diameter = webcamDiameter * 2.0
        let camW = camImg.extent.width
        let camH = camImg.extent.height
        let scale = diameter / min(camW, camH)
        camImg = camImg.transformed(by: .init(scaleX: scale, y: scale))

        // Center-crop to square
        let ext = camImg.extent
        let side = min(ext.width, ext.height)
        let crop = CGRect(x: ext.midX - side / 2, y: ext.midY - side / 2,
                          width: side, height: side)
        camImg = camImg.cropped(to: crop)

        // Shape mask
        let masked: CIImage
        let cornerRadius = side * currentShape.cornerRadiusFraction

        if currentShape == .circle {
            // Circle: radial gradient mask (smooth edges)
            let r = side / 2
            let center = CIVector(x: crop.midX, y: crop.midY)
            guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": center,
                "inputRadius0": r - 2,
                "inputRadius1": r,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.clear
            ])?.outputImage else { return nil }

            masked = camImg.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: gradient.cropped(to: crop)
            ])
        } else {
            // Rounded rect or rectangle: CoreGraphics mask
            let maskSize = CGSize(width: side, height: side)
            let renderer = CGContext(
                data: nil, width: Int(maskSize.width), height: Int(maskSize.height),
                bitsPerComponent: 8, bytesPerRow: Int(maskSize.width),
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
            if let ctx = renderer {
                ctx.setFillColor(CGColor(gray: 0, alpha: 1))
                ctx.fill(CGRect(origin: .zero, size: maskSize))
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                let path = CGPath(
                    roundedRect: CGRect(origin: .zero, size: maskSize),
                    cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                    transform: nil
                )
                ctx.addPath(path)
                ctx.fillPath()
                if let maskCGImage = ctx.makeImage() {
                    var maskCI = CIImage(cgImage: maskCGImage)
                    // Translate mask to match crop origin
                    maskCI = maskCI.transformed(by: .init(translationX: crop.origin.x, y: crop.origin.y))
                    masked = camImg.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: CIImage.empty(),
                        kCIInputMaskImageKey: maskCI.cropped(to: crop)
                    ])
                } else {
                    masked = camImg
                }
            } else {
                masked = camImg
            }
        }

        // Position: convert normalized center to pixel coords (CIImage: origin bottom-left)
        let nc = webcamNormalizedCenter
        let targetX = nc.x * w
        let targetY = (1.0 - nc.y) * h  // Flip Y for CI
        let tx = targetX - side / 2 - crop.origin.x
        let ty = targetY - side / 2 - crop.origin.y
        let placed = masked.transformed(by: .init(translationX: tx, y: ty))

        let composited = placed.composited(over: screenImg)

        // Render to output buffer
        let pool = getPool(width: Int(w), height: Int(h))
        var outBuf: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuf)
        }
        guard let out = outBuf else { return nil }
        ciContext.render(composited, to: out)
        return out
    }

    // MARK: - Full Camera Rendering (Camera Only mode)

    /// Renders the camera frame scaled to fill the entire output resolution (aspect-fill, center-cropped).
    private func renderFullCamera(camera: CVPixelBuffer, outputWidth: Int, outputHeight: Int) -> CVPixelBuffer? {
        var camImg = CIImage(cvPixelBuffer: camera)
        let outW = CGFloat(outputWidth)
        let outH = CGFloat(outputHeight)

        // Aspect-fill: scale so camera fills the entire output frame
        let camW = camImg.extent.width
        let camH = camImg.extent.height
        let scaleX = outW / camW
        let scaleY = outH / camH
        let scale = max(scaleX, scaleY) // Aspect-fill (no black bars)
        camImg = camImg.transformed(by: .init(scaleX: scale, y: scale))

        // Center crop to output size
        let scaledW = camW * scale
        let scaledH = camH * scale
        let cropRect = CGRect(
            x: (scaledW - outW) / 2,
            y: (scaledH - outH) / 2,
            width: outW,
            height: outH
        )
        camImg = camImg.cropped(to: cropRect)

        // Move to origin (0,0) since crop keeps original coords
        camImg = camImg.transformed(by: .init(translationX: -cropRect.origin.x, y: -cropRect.origin.y))

        let pool = getPool(width: outputWidth, height: outputHeight)
        var outBuf: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuf)
        }
        guard let out = outBuf else { return nil }
        ciContext.render(camImg, to: out)
        return out
    }

    // MARK: - Click Highlight Rendering

    private func renderClickHighlights(on pixelBuffer: CVPixelBuffer, highlights: [ClickHighlight]) -> CVPixelBuffer? {
        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let now = CACurrentMediaTime()

        var baseImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Clean up expired highlights
        configLock.withLock {
            _clickHighlights.removeAll { now - $0.timestamp > $0.duration }
        }

        for highlight in highlights {
            let age = now - highlight.timestamp
            guard age < highlight.duration else { continue }

            let progress = CGFloat(age / highlight.duration)
            let alpha = 1.0 - progress
            let radius = 20.0 + progress * 40.0  // Expanding ring

            // Position in pixel coords
            let px = highlight.position.x * w
            let py = (1.0 - highlight.position.y) * h  // Flip Y for CIImage

            let ringCenter = CIVector(x: px, y: py)

            // Inner transparent, outer colored ring
            guard let innerGrad = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": ringCenter,
                "inputRadius0": max(radius - 4, 0),
                "inputRadius1": radius,
                "inputColor0": CIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: alpha * 0.9),
                "inputColor1": CIColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 0)
            ])?.outputImage else { continue }

            let ringImage = innerGrad.cropped(to: CGRect(x: px - radius - 10, y: py - radius - 10,
                                                          width: (radius + 10) * 2, height: (radius + 10) * 2))
            baseImage = ringImage.composited(over: baseImage)
        }

        // Render result
        let pool = getPool(width: Int(w), height: Int(h))
        var outBuf: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuf)
        }
        guard let out = outBuf else { return nil }
        ciContext.render(baseImage, to: out)
        return out
    }

    // MARK: - Keystroke Rendering

    private func renderKeystroke(on pixelBuffer: CVPixelBuffer, keystroke: KeystrokeDisplay) -> CVPixelBuffer? {
        let now = CACurrentMediaTime()
        let age = now - keystroke.timestamp
        guard age < keystroke.duration else {
            configLock.withLock { _currentKeystroke = nil }
            return nil
        }

        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

        // Create text image using CoreText
        let fontSize: CGFloat = 28.0
        let font = CTFontCreateWithName("SF Pro Rounded" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrString = NSAttributedString(string: keystroke.text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let pillWidth = bounds.width + 32
        let pillHeight = bounds.height + 16

        // Draw pill badge
        let size = CGSize(width: pillWidth, height: pillHeight)
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        )
        guard let rep = bitmapRep,
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let cgCtx = ctx.cgContext
        cgCtx.scaleBy(x: 2, y: 2)

        // Draw rounded rect background
        let pillRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let path = CGPath(roundedRect: pillRect, cornerWidth: size.height / 2, cornerHeight: size.height / 2, transform: nil)
        cgCtx.addPath(path)
        cgCtx.setFillColor(NSColor(white: 0.1, alpha: 0.85).cgColor)
        cgCtx.fillPath()

        // Draw border
        cgCtx.addPath(path)
        cgCtx.setStrokeColor(NSColor(white: 0.4, alpha: 0.6).cgColor)
        cgCtx.setLineWidth(1)
        cgCtx.strokePath()

        // Draw text
        let textX = (size.width - bounds.width) / 2
        let textY = (size.height - bounds.height) / 2 + bounds.height * 0.15
        cgCtx.textPosition = CGPoint(x: textX, y: textY)
        CTLineDraw(line, cgCtx)

        NSGraphicsContext.restoreGraphicsState()

        // Convert to CIImage
        guard let cgImage = rep.cgImage else { return nil }
        var badgeImage = CIImage(cgImage: cgImage)

        // Fade out in last 0.5 seconds
        let alpha: CGFloat
        if age > keystroke.duration - 0.5 {
            alpha = CGFloat((keystroke.duration - age) / 0.5)
        } else {
            alpha = 1.0
        }

        if alpha < 1.0 {
            badgeImage = badgeImage.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
            ])
        }

        // Scale badge for retina
        let badgeScale = 1.0  // Already at 2x from NSBitmapImageRep
        badgeImage = badgeImage.transformed(by: .init(scaleX: badgeScale, y: badgeScale))

        // Position at bottom center
        let badgeW = badgeImage.extent.width
        let badgeH = badgeImage.extent.height
        let tx = (w - badgeW) / 2
        let ty = h * 0.05  // 5% from bottom
        badgeImage = badgeImage.transformed(by: .init(translationX: tx, y: ty))

        let baseImage = CIImage(cvPixelBuffer: pixelBuffer)
        let composited = badgeImage.composited(over: baseImage)

        let pool = getPool(width: Int(w), height: Int(h))
        var outBuf: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuf)
        }
        guard let out = outBuf else { return nil }
        ciContext.render(composited, to: out)
        return out
    }

    private func getPool(width: Int, height: Int) -> CVPixelBufferPool? {
        if let pool = outputPool { return pool }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        outputPool = pool
        return pool
    }

    // MARK: - Caption Rendering

    private func renderCaption(on pixelBuffer: CVPixelBuffer, text: String, style: CaptionStyle) -> CVPixelBuffer? {

        let w = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let h = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        // --- Word Chunking Logic ---
            let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            guard !words.isEmpty else { return pixelBuffer }

            // This ensures that words 1-3 show, then at word 4, 1-3 disappear and 4-6 show
            let maxWords = 5
            let chunkIndex = (words.count - 1) / maxWords
            let startIndex = chunkIndex * maxWords
            let endIndex = min(startIndex + maxWords, words.count)
            let displayText = words[startIndex..<endIndex].joined(separator: " ")
            // ---------------------------

            let fontSize = style.fontSize * (w / 1920.0)
            let font = NSFont.systemFont(ofSize: fontSize, weight: NSFont.Weight(rawValue: style.fontWeight.ctFontWeight))

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: style.textColor.nsColor,
                .paragraphStyle: paragraphStyle
            ]

            let attrString = NSAttributedString(string: displayText, attributes: attributes)
            let maxTextWidth = w * 0.8
            
            // Calculate bounds based on the 3-word chunk
            let textBounds = attrString.boundingRect(
                with: CGSize(width: maxTextWidth, height: font.ascender - font.descender + font.leading),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )



        // ✅ Reset ONLY when text changes
        if text != lastCaptionText {
            captionState.reset(
                with: text,
                maxWidth: maxTextWidth,
                attributes: attributes
            )
            lastCaptionText = text
        }


        // ✅ Move to next chunk after ~50% width
        captionState.advanceIfNeeded(
            progressWidth: textBounds.width,
            threshold: w * 0.5
        )

        // Padding
        let paddingH: CGFloat = 24
        let paddingV: CGFloat = 12

        let pillWidth = min(textBounds.width + paddingH * 2, w * 0.9)
        let pillHeight = textBounds.height + paddingV * 2

        let scale: CGFloat = 2.0

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pillWidth * scale),
            pixelsHigh: Int(pillHeight * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ),
        let gfxCtx = NSGraphicsContext(bitmapImageRep: bitmapRep)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gfxCtx

        let cgCtx = gfxCtx.cgContext
        cgCtx.scaleBy(x: scale, y: scale)

        // Background
        let cornerRadius: CGFloat = pillHeight / 3
        let pillRect = CGRect(x: 0, y: 0, width: pillWidth, height: pillHeight)

        let path = CGPath(
            roundedRect: pillRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        cgCtx.addPath(path)
        cgCtx.setFillColor(
            style.backgroundColor.nsColor
                .withAlphaComponent(style.backgroundOpacity)
                .cgColor
        )
        cgCtx.fillPath()

        // Text
        let textRect = CGRect(
            x: (pillWidth - textBounds.width) / 2,
            y: (pillHeight - textBounds.height) / 2,
            width: textBounds.width,
            height: textBounds.height
        )

        attrString.draw(in: textRect)

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = bitmapRep.cgImage else { return nil }

        var captionImage = CIImage(cgImage: cgImage)

        // Position
        let tx = (w - captionImage.extent.width) / 2
        let ty = h * style.position.normalizedY - captionImage.extent.height / 2

        captionImage = captionImage.transformed(by: .init(translationX: tx, y: ty))

        let baseImage = CIImage(cvPixelBuffer: pixelBuffer)
        let composited = captionImage.composited(over: baseImage)

        let pool = getPool(width: Int(w), height: Int(h))
        var outBuf: CVPixelBuffer?

        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuf)
        }

        guard let out = outBuf else { return nil }

        ciContext.render(composited, to: out)
        return out
    }
    
}
final class CaptionState {

    private(set) var chunks: [String] = []
    private var currentIndex: Int = 0

    func reset(with text: String,
               maxWidth: CGFloat,
               attributes: [NSAttributedString.Key: Any]) {

        chunks = split(text: text, maxWidth: maxWidth, attributes: attributes)
        currentIndex = 0
    }

    func currentText() -> String {
        guard currentIndex < chunks.count else { return "" }
        return chunks[currentIndex]
    }

    func advanceIfNeeded(progressWidth: CGFloat, threshold: CGFloat) {
        guard progressWidth > threshold else { return }
        currentIndex = min(currentIndex + 1, chunks.count - 1)
    }

    private func split(
        text: String,
        maxWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> [String] {

        var result: [String] = []
        var currentLine = ""

        let words = text.split(separator: " ")

        for word in words {

            let testLine = currentLine.isEmpty
                ? String(word)
                : currentLine + " " + word

            let attr = NSAttributedString(string: testLine, attributes: attributes)

            let rect = attr.boundingRect(
                with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin]
            )

            // 🚨 STRICT WIDTH CHECK (no wrapping allowed)
            if rect.width > maxWidth {

                if !currentLine.isEmpty {
                    result.append(currentLine)
                }

                currentLine = String(word)

            } else {
                currentLine = testLine
            }
        }

        if !currentLine.isEmpty {
            result.append(currentLine)
        }

        return result
    }
}
