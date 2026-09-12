import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

/// What a Trusted Circle QR code / shared code actually carries: not just
/// the patientId, but the patient's own name/phone/carrier too. Carrying
/// the patient's identity is what makes circles reciprocal -- when you
/// scan someone's code, your app has enough to also add *them* to *your*
/// circle in the same step, not just add you to theirs.
struct CircleInvitePayload: Codable {
    var patientId: String
    var name: String
    var phone: String?
    var carrier: String?
}

/// Generates/parses a scannable QR payload for joining a Trusted Circle.
enum QRCodeGenerator {
    private static let prefix = "lifeoptimizer:circle:"

    static func joinPayload(_ invite: CircleInvitePayload) -> String {
        guard let json = try? JSONEncoder().encode(invite), let jsonString = String(data: json, encoding: .utf8) else {
            return prefix + invite.patientId
        }
        return prefix + jsonString
    }

    /// Parses a scanned (or manually typed) code back into an invite.
    /// Manually-typed codes only ever carry the bare patientId (no name
    /// gets typed in), so `name` falls back to a generic placeholder in
    /// that case -- reciprocal add still works, just with a less specific
    /// display name until the two devices' real names sync some other way.
    static func parseInvite(fromScanned payload: String) -> CircleInvitePayload {
        guard payload.hasPrefix(prefix) else {
            return CircleInvitePayload(patientId: payload, name: "Circle owner")
        }
        let rest = String(payload.dropFirst(prefix.count))
        if let data = rest.data(using: .utf8),
           let invite = try? JSONDecoder().decode(CircleInvitePayload.self, from: data) {
            return invite
        }
        // Old-format QR (bare patientId after the prefix, from before
        // invites carried identity) -- still works, just not reciprocal.
        return CircleInvitePayload(patientId: rest, name: "Circle owner")
    }

    static func image(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        // The raw CIImage is tiny (e.g. ~25x25px) -- scale up so it isn't
        // blurry when displayed at a reasonable on-screen size.
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Wraps VisionKit's DataScannerViewController to scan a QR code and
/// report its decoded string via `onScan`. Camera-only -- not available
/// in Simulator (`DataScannerViewController.isSupported` is false there;
/// callers should check that before presenting this and fall back to
/// manual code entry).
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    // VisionKit calls this delegate method on its own
                    // scanning-pipeline thread, not necessarily the main
                    // thread. `onScan` mutates SwiftUI @State (joinCode,
                    // showScanner) -- doing that off the main thread is
                    // undefined and is exactly why the scan sheet was
                    // getting stuck "loading" indefinitely instead of
                    // dismissing: the state change wasn't reliably
                    // reaching the view hierarchy.
                    DispatchQueue.main.async {
                        self.onScan(payload)
                    }
                    return
                }
            }
        }
    }
}
