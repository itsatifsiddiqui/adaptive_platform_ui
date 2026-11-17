import Flutter
import UIKit

/// Streams where UIKit puts a top bar in this window
/// (`UIView.edgeInsets(for: .bar(onEdge: .top, extent:))`, iOS 27.1) to Dart,
/// as the bar's top in points, or "unsupported" before iOS 27.1.
///
/// On the open iPhone Duo in portrait the safe area starts below the status
/// island (82 pt), but system bars sit in the island's row, so the bar's top
/// is well above the safe area. On other iPhones it equals the safe area top.
final class TopBarStreamHandler: NSObject, FlutterStreamHandler {
    private let registrar: FlutterPluginRegistrar
    private var sink: FlutterEventSink?
    private var observer: EdgeObserverView?
    private var lastSent: Any?
    private var generation = 0

    init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        super.init()
    }

    func onListen(
        withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        generation += 1
        observer?.removeFromSuperview()
        observer = nil
        lastSent = nil
        sink = events
        attach(attempt: 0, generation: generation)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        generation += 1
        observer?.removeFromSuperview()
        observer = nil
        sink = nil
        lastSent = nil
        return nil
    }

    /// Retries until the Flutter view is in a window, like VerticalBarEdgeStreamHandler.
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
        view.onChange = { [weak self] v in self?.send(Self.barTop(of: v)) }
        host.insertSubview(view, at: 0)
        observer = view
        send(Self.barTop(of: view))
    }

    private func send(_ value: Any) {
        if let last = lastSent as? Double, let new = value as? Double, last == new { return }
        if let last = lastSent as? String, let new = value as? String, last == new { return }
        lastSent = value
        sink?(value)
    }

    static func barTop(of view: UIView) -> Any {
        guard #available(iOS 27.1, *) else { return "unsupported" }
        return Double(view.edgeInsets(for: .bar(onEdge: UIRectEdge.top, extent: 44)).top)
    }
}
