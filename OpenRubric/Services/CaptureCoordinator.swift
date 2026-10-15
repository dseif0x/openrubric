import AppKit
import CoreGraphics
import Combine
import SwiftUI

/// Orchestrates the full capture→OCR→solve→deliver pipeline.
final class CaptureCoordinator: ObservableObject {
    static let shared = CaptureCoordinator()

    @Published var isProcessing = false
    @Published var lastStatus: String = ""

    private var solveTask: Task<Void, Never>?

    func triggerCaptureAndSolve() {
        guard !isProcessing else { return }

        let settings = SettingsStore.shared
        guard settings.isConfigured else {
            Task { @MainActor in
                AnswerDelivery.shared.setError("No provider configured. Open Settings to add your API endpoint and key.")
            }
            OverlayController.shared.showError("No provider configured.\nOpen Settings (⌘,) to add your endpoint + key.")
            return
        }

        isProcessing = true
        Task { @MainActor in
            AnswerDelivery.shared.setWorking("Capturing…")
        }

        solveTask = Task { @MainActor in
            defer {
                isProcessing = false
            }

            let mode = settings.currentMode

            // 1. Capture
            let capture: ScreenCaptureService.CaptureResult
            do {
                capture = try await ScreenCaptureService.shared.captureDisplayUnderPointer()
            } catch {
                let msg = "Screen capture failed: \(error.localizedDescription)\nCheck Screen Recording permission in System Settings → Privacy & Security."
                AnswerDelivery.shared.setError(msg)
                if mode == .remote { OverlayController.shared.showError("Screen capture failed.\nCheck Screen Recording permission.") }
                return
            }

            AnswerDelivery.shared.setWorking("Reading…")

            // Pointer position relative to display origin, scaled to image pixels
            let pointerInDisplay = CGPoint(
                x: capture.pointerLocation.x - capture.displayBounds.minX,
                y: capture.pointerLocation.y - capture.displayBounds.minY
            )
            let pointerInImage = CGPoint(
                x: pointerInDisplay.x * capture.scale,
                y: pointerInDisplay.y * capture.scale
            )

            // 2. OCR anchor
            let anchor = await OCRService.shared.findAnchorText(
                cgImage: capture.image,
                pointerInImage: pointerInImage
            )

            AnswerDelivery.shared.setWorking("Solving…")

            // 3. Draw the pink marker on the image (adds visual anchor for the model)
            let markedBase64 = Self.drawMarker(
                on: capture.image,
                pointerInImage: pointerInImage
            ) ?? capture.pngBase64

            // 4. Build pointer description string
            let pointerDesc = String(
                format: "(%.0f, %.0f) pixels",
                pointerInImage.x, pointerInImage.y
            )

            // 5. Call the AI
            switch mode {
            case .remote:
                await solveFreeform(imageBase64: markedBase64, pointerDescription: pointerDesc, anchor: anchor?.text)
            case .cbt, .capsLock, .keyboardBacklight, .flash:
                await solveMultipleChoice(imageBase64: markedBase64, pointerDescription: pointerDesc, anchor: anchor?.text)
            }
        }
    }

    // MARK: - Solve paths

    @MainActor
    private func solveMultipleChoice(imageBase64: String, pointerDescription: String, anchor: String?) async {
        do {
            let response = try await AIService.shared.solveMultipleChoice(
                imageBase64: imageBase64,
                pointerDescription: pointerDescription,
                ocrAnchor: anchor
            )

            guard let first = response.answers.first, !first.answer.isEmpty else {
                AnswerDelivery.shared.setError("No valid answers returned.")
                return
            }
            AnswerDelivery.shared.deliver(first.answer, mode: SettingsStore.shared.currentMode)
        } catch {
            AnswerDelivery.shared.setError("Solve failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func solveFreeform(imageBase64: String, pointerDescription: String, anchor: String?) async {
        OverlayController.shared.answerText = ""
        OverlayController.shared.isStreaming = true
        OverlayController.shared.errorMessage = nil
        OverlayController.shared.show()

        let stream = AIService.shared.solveFreeformStream(
            imageBase64: imageBase64,
            pointerDescription: pointerDescription,
            ocrAnchor: anchor
        )

        do {
            for try await chunk in stream {
                let current = OverlayController.shared.answerText
                OverlayController.shared.updateStream(current + chunk)
            }
            OverlayController.shared.streamFinished()
        } catch {
            OverlayController.shared.showError("Solve failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Marker drawing

    /// Draws a bright pink target ring + crosshair at the pointer position on the captured image.
    static func drawMarker(on cgImage: CGImage, pointerInImage: CGPoint) -> String? {
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw original image (CG origin is bottom-left, but we want top-left pointer coords)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Convert top-left pointer Y to CG bottom-left coordinates
        let cy = CGFloat(height) - pointerInImage.y
        let cx = pointerInImage.x

        // Pink target ring
        let ringRadius: CGFloat = 28
        ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0.75, alpha: 0.95))
        ctx.setLineWidth(5)
        ctx.strokeEllipse(in: CGRect(x: cx - ringRadius, y: cy - ringRadius, width: ringRadius * 2, height: ringRadius * 2))

        // Crosshair
        ctx.setLineWidth(3)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx - 40, y: cy))
        ctx.addLine(to: CGPoint(x: cx + 40, y: cy))
        ctx.move(to: CGPoint(x: cx, y: cy - 40))
        ctx.addLine(to: CGPoint(x: cx, y: cy + 40))
        ctx.strokePath()

        // Center dot
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0.75, alpha: 1))
        let dotRadius: CGFloat = 6
        ctx.fillEllipse(in: CGRect(x: cx - dotRadius, y: cy - dotRadius, width: dotRadius * 2, height: dotRadius * 2))

        guard let output = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: output)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png.base64EncodedString()
    }
}
