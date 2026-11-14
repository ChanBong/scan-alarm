import SwiftUI
import VisionKit

/// Live camera view that reports the text of every barcode or QR code it sees.
struct ScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void

    static var isUsable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onScan = onScan
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            report(updatedItems)
        }

        private func report(_ items: [RecognizedItem]) {
            for item in items {
                if case .barcode(let code) = item, let value = code.payloadStringValue {
                    onScan(value)
                }
            }
        }
    }
}
