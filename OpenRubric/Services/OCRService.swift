import Vision
import AppKit

/// Runs on-device OCR via the Vision framework to locate the text nearest the pointer.
final class OCRService: @unchecked Sendable {
    static let shared = OCRService()

    struct OCRAnchor: Sendable {
        let text: String
        let boundingBox: CGRect  // normalized (0..1, bottom-left origin, Vision convention)
    }

    /// Perform OCR on the captured image and find the observation closest to the pointer location.
    /// - Parameters:
    ///   - cgImage: the full-display screenshot
    ///   - pointerInImage: pointer position in image pixel coordinates (top-left origin)
    func findAnchorText(cgImage: CGImage, pointerInImage: CGPoint) async -> OCRAnchor? {
        let pointer = pointerInImage
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Create Vision objects inside this closure so they never cross
                // a concurrency domain — no Sendable conformance needed.
                let request = VNRecognizeTextRequest { request, error in
                    guard error == nil,
                          let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: nil)
                        return
                    }

                    // Find the observation whose bounding box center is nearest the pointer
                    var best: (obs: VNRecognizedTextObservation, dist: CGFloat)?
                    for obs in observations {
                        let box = obs.boundingBox // normalized, bottom-left origin
                        let center = CGPoint(x: box.midX, y: box.midY)
                        let dx = center.x - pointer.x / CGFloat(imageWidth)
                        let dy = center.y - (1.0 - pointer.y / CGFloat(imageHeight))
                        let dist = dx * dx + dy * dy
                        if best == nil || dist < best!.dist {
                            best = (obs, dist)
                        }
                    }

                    guard let winner = best,
                          let topCandidate = winner.obs.topCandidates(1).first else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: OCRAnchor(
                        text: topCandidate.string,
                        boundingBox: winner.obs.boundingBox
                    ))
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["ko-KR", "en-US"]

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
