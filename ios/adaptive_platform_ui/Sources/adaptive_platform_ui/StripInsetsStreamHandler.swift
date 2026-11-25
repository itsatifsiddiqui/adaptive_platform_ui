import Flutter
import UIKit

/// Streams the room UIKit gives a vertical bar on each side of this window
/// (`UIView.edgeInsets(for: .bar(onEdge:extent:))`, iOS 27.1) to Dart, with the
/// window size and safe area it was read for, or "unsupported" before iOS 27.1.
final class StripInsetsStreamHandler: NSObject, FlutterStreamHandler {
    private let registrar: FlutterPluginRegistrar
    private var sink: FlutterEventSink?
    private var observer: UIView?
    private var lastSent: [String: Double]?
    private var generation = 0

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        stopObserving()
        sink = events
        guard #available(iOS 27.1, *) else {
            events("unsupported")
            return nil
        }
        attach(attempt: 0, generation: generation)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopObserving()
        sink = nil
        return nil
    }

    private func stopObserving() {
        generation += 1
        observer?.removeFromSuperview()
        observer = nil
        lastSent = nil
    }

    /// Retries until the Flutter view is in a window, like VerticalBarEdgeStreamHandler.
    @available(iOS 27.1, *)
    private func attach(attempt: Int, generation: Int) {
        guard generation == self.generation, sink != nil, observer == nil else { return }
        guard let host = registrar.viewController?.view, host.window != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt < 20 ? 0.05 : 0.5)) { [weak self] in
                self?.attach(attempt: attempt + 1, generation: generation)
            }
            return
        }
        let view = EdgeObserverView(frame: host.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        let report: (UIView) -> Void = { [weak self, weak view] _ in
            guard let view = view else { return }
            self?.send(Self.reading(of: view))
        }
        view.onChange = report
        // UIKit has no callback for this inset and the window keeps its size when the island grows.
        // Views pinned to UIKit's own bar guides change size with it, so they get a layout pass.
        for edge in [UIRectEdge.left, .right] {
            let pinned = EdgeObserverView()
            pinned.onChange = report
            pinned.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(pinned)
            let guide = view.layoutGuide(for: .bar(onEdge: edge, extent: Self.barExtent))
            NSLayoutConstraint.activate([
                pinned.topAnchor.constraint(equalTo: guide.topAnchor),
                pinned.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
                pinned.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                pinned.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            ])
        }
        host.insertSubview(view, at: 0)
        observer = view
        send(Self.reading(of: view))
    }

    private func send(_ reading: [String: Double]) {
        // Out of the window there is no strip to read, as while the window's root is swapped.
        guard observer?.window != nil, reading != lastSent else { return }
        lastSent = reading
        sink?(reading)
    }

    /// Width of the controls, the same as IOS26GlassCapsule.width in Dart.
    private static let barExtent: CGFloat = 48

    @available(iOS 27.1, *)
    private static func reading(of view: UIView) -> [String: Double] {
        let left = view.edgeInsets(for: .bar(onEdge: UIRectEdge.left, extent: barExtent))
        let right = view.edgeInsets(for: .bar(onEdge: UIRectEdge.right, extent: barExtent))
        return [
            "width": Double(view.bounds.width),
            "height": Double(view.bounds.height),
            "safeLeft": Double(view.safeAreaInsets.left),
            "safeRight": Double(view.safeAreaInsets.right),
            "leftTop": Double(left.top),
            "leftBottom": Double(left.bottom),
            "rightTop": Double(right.top),
            "rightBottom": Double(right.bottom),
        ]
    }
}
