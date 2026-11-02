import Flutter
import UIKit

/// Presents the existing Flutter controller in a real UIKit sheet. Keeping one
/// controller/engine preserves providers, navigation, plugins and live capture.
enum RecordingDetailSheetRegistration {
    private static var coordinator: RecordingDetailSheetCoordinator?

    static func register(messenger: FlutterBinaryMessenger) {
        coordinator = RecordingDetailSheetCoordinator(messenger: messenger)
    }
}

private final class RecordingDetailSheetCoordinator: NSObject, UIAdaptivePresentationControllerDelegate {
    private let channel: FlutterMethodChannel
    private var identity: Int?
    private weak var window: UIWindow?
    private var flutter: FlutterViewController?
    private var backdrop: RecordingSheetBackdrop?
    private var sheet: FlutterViewController?
    private var originalPresentationStyle: UIModalPresentationStyle = .automatic
    private var cover: UIImageView?
    private var restoring = false

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "com.omi/recording_detail_sheet", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, reply in self?.handle(call, reply: reply) }
    }

    private func handle(_ call: FlutterMethodCall, reply: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        if call.method == "prepare" {
            guard let id = args["id"] as? Int else { reply(false); return }
            reply(prepare(id: id))
            return
        }
        guard let id = args["id"] as? Int, id == identity else { reply(nil); return }
        switch call.method {
        case "present":
            present(reply: reply)
        case "dismiss":
            guard let sheet, sheet.presentingViewController != nil else {
                restore()
                reply(nil)
                return
            }
            sheet.dismiss(animated: true) { [weak self] in self?.restore(); reply(nil) }
        case "setDismissible":
            sheet?.isModalInPresentation = args["enabled"] as? Bool != true
            reply(nil)
        case "restored":
            restoreController(reply: reply)
        default:
            reply(FlutterMethodNotImplemented)
        }
    }

    private func prepare(id: Int) -> Bool {
        guard identity == nil,
              let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }),
              let flutter = window.rootViewController as? FlutterViewController,
              flutter.presentedViewController == nil else { return false }
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = window.screen.scale
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        self.window = window
        self.flutter = flutter
        originalPresentationStyle = flutter.modalPresentationStyle
        identity = id
        backdrop = RecordingSheetBackdrop(image: image, statusBarStyle: flutter.preferredStatusBarStyle)
        let cover = UIImageView(image: image)
        cover.frame = window.bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.isUserInteractionEnabled = true
        cover.accessibilityElementsHidden = true
        window.addSubview(cover)
        self.cover = cover
        return true
    }

    private func present(reply: @escaping FlutterResult) {
        guard let window, let flutter, let backdrop, sheet == nil, !restoring else {
            reply(FlutterError(code: "sheet_unavailable", message: "Recording sheet is unavailable", details: nil))
            return
        }
        // Present Flutter itself, rather than a full-screen Flutter child inside
        // another controller. UIKit can now deliver the sheet's real safe area.
        window.rootViewController = backdrop
        flutter.modalPresentationStyle = .pageSheet
        flutter.view.accessibilityViewIsModal = true
        flutter.isModalInPresentation = false
        if let presentation = flutter.sheetPresentationController {
            presentation.detents = [.large()]
            presentation.prefersGrabberVisible = true
            presentation.prefersScrollingExpandsWhenScrolledToEdge = true
            presentation.prefersEdgeAttachedInCompactHeight = true
            presentation.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        }
        sheet = flutter
        flutter.presentationController?.delegate = self
        cover?.removeFromSuperview()
        cover = nil
        backdrop.present(flutter, animated: true) { reply(nil) }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === sheet else { return }
        restore()
    }

    private func restore() {
        guard !restoring, let window, flutter != nil, let backdrop, let id = identity else { return }
        restoring = true
        // Keep the native Home image visible while Dart pops detail and builds
        // Home offscreen. Reattaching the controller first exposed stale sheet frames.
        let cover = UIImageView(image: backdrop.image)
        cover.frame = window.bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.isUserInteractionEnabled = true
        cover.accessibilityElementsHidden = true
        window.addSubview(cover)
        self.cover = cover
        channel.invokeMethod("didDismiss", arguments: ["id": id])
    }

    private func restoreController(reply: @escaping FlutterResult) {
        guard restoring, let window, let flutter, let id = identity else { reply(nil); return }
        guard window.rootViewController !== flutter else {
            finishRestoration()
            reply(nil)
            return
        }
        // This callback is tied to the recreated native rendering surface, not
        // an arbitrary delay or the end of Dart's layout pass.
        flutter.setFlutterViewDidRenderCallback { [weak self] in
            guard let self, self.identity == id else { reply(nil); return }
            DispatchQueue.main.async {
                self.finishRestoration()
                reply(nil)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        flutter.modalPresentationStyle = originalPresentationStyle
        flutter.view.accessibilityViewIsModal = false
        flutter.isModalInPresentation = false
        // A dismissed sheet may retain its presentation transform/container
        // until UIKit's cleanup completes. Restore a plain root view explicitly.
        flutter.view.removeFromSuperview()
        flutter.view.layer.removeAllAnimations()
        flutter.view.transform = .identity
        flutter.view.frame = window.bounds
        flutter.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.rootViewController = flutter
        if let cover {
            cover.frame = window.bounds
            window.addSubview(cover)
        }
        flutter.view.setNeedsLayout()
        flutter.view.layoutIfNeeded()
        CATransaction.commit()
    }

    private func finishRestoration() {
        cover?.removeFromSuperview()
        cover = nil
        identity = nil
        flutter = nil
        backdrop = nil
        sheet = nil
        restoring = false
    }

}

private final class RecordingSheetBackdrop: UIViewController {
    let image: UIImage
    private let statusBarStyle: UIStatusBarStyle
    init(image: UIImage, statusBarStyle: UIStatusBarStyle) {
        self.image = image
        self.statusBarStyle = statusBarStyle
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.clipsToBounds = true
        let imageView = UIImageView(image: image)
        // UIKit resizes the presenting view while forming its background card.
        // Keep the captured screen at its original point size instead of
        // stretching its text and controls into that shorter rectangle.
        imageView.frame = CGRect(origin: .zero, size: image.size)
        imageView.contentMode = .topLeft
        imageView.accessibilityElementsHidden = true
        container.addSubview(imageView)
        view = container
    }
    override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }
}
