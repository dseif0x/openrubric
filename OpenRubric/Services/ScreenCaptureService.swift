import AppKit
import ScreenCaptureKit
import CoreGraphics

/// Captures the display containing the pointer via ScreenCaptureKit.
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    struct CaptureResult: Sendable {
        let image: CGImage
        let pngBase64: String
        let pointerLocation: CGPoint  // in screen (global) coordinates
        let displayID: CGDirectDisplayID
        let displayBounds: CGRect     // global bounds of the captured display
        let scale: Double             // backing scale factor of the display
    }

    /// Returns the display ID under the current pointer position.
    /// Uses CGEvent coordinates (top-left origin) — directly compatible with CGDisplayBounds.
    func displayUnderPointer() -> (CGDirectDisplayID, CGPoint)? {
        guard let event = CGEvent(source: nil) else { return nil }
        let point = event.location

        let maxDisplays: UInt32 = 16
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(maxDisplays, &onlineDisplays, &displayCount) == .success else {
            return nil
        }
        for i in 0..<Int(displayCount) {
            let id = onlineDisplays[i]
            let bounds = CGDisplayBounds(id)
            if bounds.contains(point) {
                return (id, point)
            }
        }
        return nil
    }

    /// Capture the display under the pointer, returning both the image and coordinate metadata.
    func captureDisplayUnderPointer() async throws -> CaptureResult {
        guard let (displayID, pointer) = displayUnderPointer() else {
            throw CaptureError.noDisplayFound
        }

        let bounds = CGDisplayBounds(displayID)
        let scale = await displayScale(displayID)

        let cgImage = try await captureWithSCK(
            displayID: displayID,
            pixelWidth: Int((bounds.width * scale).rounded()),
            pixelHeight: Int((bounds.height * scale).rounded())
        )

        guard let pngData = cgImage.pngData() else {
            throw CaptureError.encodingFailed
        }

        let base64 = pngData.base64EncodedString()

        return CaptureResult(
            image: cgImage,
            pngBase64: base64,
            pointerLocation: pointer,
            displayID: displayID,
            displayBounds: bounds,
            scale: scale
        )
    }

    /// Single-screenshot capture via SCScreenshotManager (macOS 14+).
    private func captureWithSCK(displayID: CGDirectDisplayID, pixelWidth: Int, pixelHeight: Int) async throws -> CGImage {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best
        // Capture at the display's full pixel resolution. Without this, SCStreamConfiguration
        // uses a default size that may not match displayBounds × scale, which throws off the
        // pointer-to-image mapping used to place the marker.
        if pixelWidth > 0 && pixelHeight > 0 {
            config.width = pixelWidth
            config.height = pixelHeight
        }

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
    }

    private func displayScale(_ displayID: CGDirectDisplayID) async -> Double {
        await MainActor.run {
            guard let screen = NSScreen.screens.first(where: {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
            }) else { return 2.0 }
            return screen.backingScaleFactor
        }
    }

    enum CaptureError: Error, LocalizedError {
        case noDisplayFound
        case encodingFailed
        case sckFailed(String)

        var errorDescription: String? {
            switch self {
            case .noDisplayFound: return "No display found under pointer."
            case .encodingFailed: return "Failed to encode screenshot as PNG."
            case .sckFailed(let reason): return "ScreenCaptureKit failed: \(reason)"
            }
        }
    }
}

extension CGImage {
    func pngData() -> Data? {
        let rep = NSBitmapImageRep(cgImage: self)
        return rep.representation(using: .png, properties: [:])
    }
}
