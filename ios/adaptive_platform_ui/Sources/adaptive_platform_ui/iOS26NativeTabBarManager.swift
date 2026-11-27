import Flutter
import UIKit

/// Puts the app's one Flutter view inside a real UITabBarController, so the
/// system draws the tab bar. Only a container's tab bar moves into the iPhone
/// Duo vertical bar; a bar drawn inside Flutter never does.
@available(iOS 26.0, *)
final class TabRootController: UITabBarController, UITabBarControllerDelegate {
    private let flutterViewController: FlutterViewController
    private let channel: FlutterMethodChannel
    private var tabIds: [String] = []
    private var actionId: String?
    private var itemsById: [String: NSDictionary] = [:]
    private var isHiddenByFlutter = false

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "adaptive_platform_ui/native_tab_bar",
            binaryMessenger: registrar.messenger()
        )
        var root: TabRootController?
        channel.setMethodCallHandler { call, result in
            let args = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "setTabs":
                if let root = root {
                    root.update(with: args)
                    return result(nil)
                }
                // With nothing to show, the Flutter view stays the window's root.
                guard !(args["items"] as? [Any] ?? []).isEmpty else { return result(nil) }
                guard let flutterViewController = registrar.viewController as? FlutterViewController,
                      let window = flutterViewController.view.window else {
                    return result(FlutterError(code: "no_window", message: "The Flutter view is not in a window yet", details: nil))
                }
                let controller = TabRootController(flutterViewController: flutterViewController, channel: channel)
                controller.update(with: args)
                controller.install(in: window)
                root = controller
                result(nil)
            case "setSelectedIndex":
                root?.selectTab(at: (args["index"] as? NSNumber)?.intValue ?? 0)
                result(nil)
            case "setHidden":
                root?.isHiddenByFlutter = (args["hidden"] as? NSNumber)?.boolValue ?? false
                root?.updateTabBarHidden()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private init(flutterViewController: FlutterViewController, channel: FlutterMethodChannel) {
        self.flutterViewController = flutterViewController
        self.channel = channel
        super.init(nibName: nil, bundle: nil)
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var childForStatusBarStyle: UIViewController? { selectedViewController }
    override var childForStatusBarHidden: UIViewController? { selectedViewController }
    override var childForHomeIndicatorAutoHidden: UIViewController? { selectedViewController }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        flutterViewController.supportedInterfaceOrientations
    }

    /// Swapped in once and never swapped back, so Flutter keeps one parent
    /// chain for the rest of the app's life.
    private func install(in window: UIWindow) {
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            window.rootViewController = self
        }
    }

    private func update(with args: [String: Any]) {
        let items = args["items"] as? [[String: Any]] ?? []
        let action = args["action"] as? [String: Any]
        tabIds = items.compactMap { $0["id"] as? String }
        actionId = action?["id"] as? String

        let flutterViewController = self.flutterViewController
        let newTabs = (items + [action].compactMap { $0 }).compactMap { item -> UITab? in
            guard let id = item["id"] as? String else { return nil }
            let tab = self.tab(forIdentifier: id) ?? UITab(title: "", image: nil, identifier: id) { _ in
                TabSlot(flutterViewController: flutterViewController)
            }
            apply(item, to: tab)
            return tab
        }
        if newTabs.map(\.identifier) != tabs.map(\.identifier) {
            setTabs(newTabs, animated: false)
        }

        // iOS 27 lifts the action out beside the tabs. iOS 26 has no such
        // property, so the action stays a plain tab item that never gets selected.
        // Read through KVC so the plugin still builds against SDKs older than 27.0.
        let prominentKey = "prominentTabIdentifier"
        if responds(to: NSSelectorFromString(prominentKey)) {
            setValue(actionId, forKey: prominentKey)
        }

        selectTab(at: (args["selectedIndex"] as? NSNumber)?.intValue ?? 0)
        updateTabBarHidden()
    }

    /// Updates the tab in place, so its page and the Flutter view inside it stay put.
    private func apply(_ item: [String: Any], to tab: UITab) {
        let dictionary = item as NSDictionary
        guard itemsById[tab.identifier] != dictionary else { return }
        itemsById[tab.identifier] = dictionary

        tab.title = item["title"] as? String ?? ""
        tab.badgeValue = item["badge"] as? String

        let filePath = item["filePath"] as? String ?? ""
        let networkUrl = item["networkUrl"] as? String ?? ""
        guard filePath.isEmpty && networkUrl.isEmpty else {
            let avatar = TabItemImages.loadRuntimeImage(filePath: filePath, networkURL: networkUrl)
            tab.image = (avatar ?? UIImage(systemName: "person.crop.circle"))?.withRenderingMode(.alwaysOriginal)
            if #available(iOS 26.1, *) {
                tab.selectedImage = nil
            }
            guard avatar == nil, !networkUrl.isEmpty else { return }
            TabItemImages.fetchNetworkImageIfNeeded(urlString: networkUrl) { [weak self, weak tab] image in
                // The avatar may have changed while this one downloaded.
                guard let self = self, let tab = tab, let image = image,
                      self.itemsById[tab.identifier]?["networkUrl"] as? String == networkUrl else { return }
                tab.image = image.withRenderingMode(.alwaysOriginal)
            }
            return
        }

        tab.image = Self.icon(symbol: item["sfSymbol"], asset: item["assetName"])
        // iOS 26.0 has no selected image on a tab, so it tints the plain icon instead.
        if #available(iOS 26.1, *) {
            tab.selectedImage = Self.icon(symbol: item["selectedSfSymbol"], asset: item["selectedAssetName"])
        }
    }

    /// An SF Symbol, else an image in the app's asset catalog, else a Flutter asset.
    private static func icon(symbol: Any?, asset: Any?) -> UIImage? {
        if let name = symbol as? String, !name.isEmpty {
            return (UIImage(systemName: name) ?? UIImage(named: name))?.withRenderingMode(.alwaysTemplate)
        }
        if let name = asset as? String, !name.isEmpty {
            return TabItemImages.flutterAsset(name)?.withRenderingMode(.alwaysTemplate)
        }
        return nil
    }

    /// Setting `selectedTab` in code does not call the delegate, so this never echoes back to Dart.
    private func selectTab(at index: Int) {
        guard tabIds.indices.contains(index),
              let tab = self.tab(forIdentifier: tabIds[index]),
              selectedTab !== tab else { return }
        selectedTab = tab
    }

    private func updateTabBarHidden() {
        let isHidden = isHiddenByFlutter || tabIds.isEmpty
        guard isHidden != isTabBarHidden else { return }
        setTabBarHidden(isHidden, animated: true)
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
        // The action tab runs an action, like a button, and never becomes the open tab.
        guard tab.identifier == actionId else { return true }
        channel.invokeMethod("onAction", arguments: ["id": tab.identifier])
        return false
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
        guard let index = tabIds.firstIndex(of: selectedTab.identifier) else { return }
        channel.invokeMethod("onTabSelected", arguments: ["index": index])
    }
}

/// An empty tab page. The page on screen holds the one Flutter view, which
/// draws every tab itself.
@available(iOS 26.0, *)
private final class TabSlot: UIViewController {
    private let flutterViewController: FlutterViewController

    init(flutterViewController: FlutterViewController) {
        self.flutterViewController = flutterViewController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // Flutter pauses and drops its surface when told it disappeared, which
    // would blank the screen on every tab switch.
    override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }

    override var childForStatusBarStyle: UIViewController? { children.first }
    override var childForStatusBarHidden: UIViewController? { children.first }
    override var childForHomeIndicatorAutoHidden: UIViewController? { children.first }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    // Taken over once this page is in the window, so the Flutter view moves
    // between pages without leaving the window.
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        guard flutterViewController.parent !== self else { return }
        let isFirstPage = flutterViewController.parent == nil
        if !isFirstPage {
            flutterViewController.willMove(toParent: nil)
            flutterViewController.removeFromParent()
        }
        // The view moves first, in one step: removeFromParent leaves it inside
        // the old page, and iOS 26 throws when a child joins with its view there.
        flutterViewController.view.frame = view.bounds
        flutterViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(flutterViewController.view)
        addChild(flutterViewController)
        flutterViewController.didMove(toParent: self)
        // The window told Flutter it disappeared when it stopped being the root.
        if isFirstPage {
            flutterViewController.beginAppearanceTransition(true, animated: false)
            flutterViewController.endAppearanceTransition()
        }
    }
}
