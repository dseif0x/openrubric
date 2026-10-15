import AppKit
import ScreenCaptureKit
import CoreGraphics

/// Captures the display containing the pointer, using ScreenCaptureKit on macOS 13+
/// (with a CGDisplay fallback for systems where SCK is unavailable).
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    struct CaptureResult {
        let image: NSImage
        let pngBase64: String
        let pointerLocation: CGPoint  // in screen (global) coordinates
        let displayID: CGDirectDisplayID
        let displayBounds: CGRect     // global bounds of the captured display
        let scale: Double             // backing scale factor of the display
    }

    /// Returns the display ID under the current pointer position.
    /// Uses CGEvent coordinates (top-left origin) — directly compatible with CGDisplayBounds.
    func displayUnderPointer() -> (CGDirectDisplayID, CGPoint)? {
        // CGEvent gives us the pointer in CG global coordinates (top-left origin of primary display)
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

        // Try ScreenCaptureKit first (macOS 12.3+), fall back to CGDisplayCreateImage
        let cgImage: CGImage
        if #available(macOS 12.3, *) {
            do {
                cgImage = try await captureWithSCK(displayID: displayID)
            } catch {
                cgImage = (CGDisplayCreateImage(displayID)) ?? (CGDisplayCreateImage(CGMainDisplayID()) ?? fallbackImage())
            }
        } else {
            cgImage = (CGDisplayCreateImage(displayID)) ?? fallbackImage()
        }

        guard let pngData = cgImage.pngData() else {
            throw CaptureError.encodingFailed
        }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        let base64 = pngData.base64EncodedString()

        return CaptureResult(
            image: nsImage,
            pngBase64: base64,
            pointerLocation: pointer,
            displayID: displayID,
            displayBounds: bounds,
            scale: scale
        )
    }

    @available(macOS 12.3, *)
    private func captureWithSCK(displayID: CGDirectDisplayID) async throws -> CGImage {
        let contentFilter: SCContentFilter
        do {
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
                throw CaptureError.noDisplayFound
            }
            contentFilter = SCContentFilter(display: display, excludingWindows: [])
        } catch {
            throw CaptureError.sckFailed(String(describing: error))
        }

        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.captureResolution = .best
        config.scalesToFit = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: contentFilter,
            configuration: config
        )
        return image
    }

    private func displayScale(_ displayID: CGDirectDisplayID) async -> Double {
        await MainActor.run {
            guard let screen = NSScreen.screens.first(where: {
                $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
            }) else { return 2.0 }
            return screen.backingScaleFactor
        }
    }

    private func fallbackImage() -> CGImage {
        // 1x1 transparent pixel — should never happen in practice
        let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
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
