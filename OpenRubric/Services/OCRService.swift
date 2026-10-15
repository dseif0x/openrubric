import Vision
import AppKit

/// Runs on-device OCR via the Vision framework to locate the text nearest the pointer.
final class OCRService: @unchecked Sendable {
    static let shared = OCRService()

    struct OCRAnchor: Sendable {
        let text: String
        let boundingBox: CGRect  // normalized (0..1, bottom-left origin, Vision convention)
    }

    /// Maximum time we let OCR run before giving up. The anchor is only a hint for the
    /// model, so a nil result is acceptable — but a stalled Vision request must never be
    /// allowed to hang the whole capture→solve pipeline (which would leave the UI stuck
    /// on "Reading…" and `isProcessing` wedged true).
    private static let timeout: TimeInterval = 8

    /// Guarantees a `CheckedContinuation` is resumed exactly once, no matter whether the
    /// Vision completion handler, the `perform` error path, or the timeout wins the race.
    private final class ContinuationBox: @unchecked Sendable {
        private var continuation: CheckedContinuation<OCRAnchor?, Never>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<OCRAnchor?, Never>) {
            self.continuation = continuation
        }

        func resume(_ value: OCRAnchor?, reason: String) {
            lock.lock()
            guard let continuation else {
                lock.unlock()
                return
            }
            self.continuation = nil
            lock.unlock()
            NSLog("[OpenRubric] OCR finished (\(reason))")
            continuation.resume(returning: value)
        }
    }

    /// Perform OCR on the captured image and find the observation closest to the pointer.
    /// - Parameters:
    ///   - cgImage: the full-display screenshot
    ///   - pointerInImage: pointer position in image pixel coordinates (top-left origin)
    func findAnchorText(cgImage: CGImage, pointerInImage: CGPoint) async -> OCRAnchor? {
        let pointer = pointerInImage
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height

        return await withCheckedContinuation { continuation in
            let box = ContinuationBox(continuation)

            // Safety net: if Vision stalls (large Retina capture, cold language model,
            // etc.) resume with nil so the pipeline keeps moving.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.timeout) {
                box.resume(nil, reason: "timeout")
            }

            DispatchQueue.global(qos: .userInitiated).async {
                // Create Vision objects inside this closure so they never cross
                // a concurrency domain — no Sendable conformance needed.
                let request = VNRecognizeTextRequest { request, error in
                    guard error == nil,
                          let observations = request.results as? [VNRecognizedTextObservation] else {
                        box.resume(nil, reason: "no-results")
                        return
                    }

                    // Find the observation whose bounding box center is nearest the pointer
                    var best: (obs: VNRecognizedTextObservation, dist: CGFloat)?
                    for obs in observations {
                        let boundingBox = obs.boundingBox // normalized, bottom-left origin
                        let center = CGPoint(x: boundingBox.midX, y: boundingBox.midY)
                        let dx = center.x - pointer.x / CGFloat(imageWidth)
                        let dy = center.y - (1.0 - pointer.y / CGFloat(imageHeight))
                        let dist = dx * dx + dy * dy
                        if best == nil || dist < best!.dist {
                            best = (obs, dist)
                        }
                    }

                    guard let winner = best,
                          let topCandidate = winner.obs.topCandidates(1).first else {
                        box.resume(nil, reason: "no-candidate")
                        return
                    }
                    box.resume(OCRAnchor(
                        text: topCandidate.string,
                        boundingBox: winner.obs.boundingBox
                    ), reason: "matched")
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["ko-KR", "en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    box.resume(nil, reason: "perform-threw: \(error.localizedDescription)")
                }
            }
        }
    }
}
