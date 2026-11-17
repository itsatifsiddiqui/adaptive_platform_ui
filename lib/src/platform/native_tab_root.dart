import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/adaptive_scaffold.dart';
import '../widgets/ios26/native_tab_icons.dart';
import 'platform_info.dart';

/// A button that sits in the native tab bar beside the tabs, such as Create.
/// Tapping it runs [onPressed]; it never becomes the open tab.
class NativeTabAction {
  const NativeTabAction({
    required this.sfSymbol,
    required this.label,
    required this.onPressed,
  });

  final String sfSymbol;
  final String label;
  final VoidCallback onPressed;
}

/// Hands the tabs to a real `UITabBarController` that holds the whole Flutter
/// view, so iOS draws the tab bar itself: Liquid Glass at the bottom, or in
/// the vertical bar on iPhone Duo. Draws nothing in Flutter.
///
/// The bar hides while another route (a page, sheet or dialog) covers the
/// route this widget is in, since it sits above everything Flutter draws.
class NativeRootTabBar extends StatefulWidget {
  const NativeRootTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
    this.action,
  });

  final List<AdaptiveNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final NativeTabAction? action;

  /// iOS 27 is the first to put a container's tab bar in the iPhone Duo's
  /// vertical bar, and the native side only runs there.
  static bool get isSupported =>
      PlatformInfo.isIOS && PlatformInfo.iOSVersion >= 27;

  @override
  State<NativeRootTabBar> createState() => _NativeRootTabBarState();
}

class _NativeRootTabBarState extends State<NativeRootTabBar> {
  static const _channel = MethodChannel('adaptive_platform_ui/native_tab_bar');
  static const _actionId = 'action';

  /// There is one native bar per app, so only the newest widget drives it.
  /// An older one going away must not hide the bar the new one shows.
  static _NativeRootTabBarState? _owner;

  String? _lastTabs;
  int? _lastIndex;
  bool? _lastHidden;

  @override
  void initState() {
    super.initState();
    _owner = this;
    _channel.setMethodCallHandler(_onNativeCall);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant NativeRootTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    if (_owner == this) {
      _owner = null;
      _channel.setMethodCallHandler(null);
      unawaited(_channel.invokeMethod('setHidden', {'hidden': true}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  void _sync() {
    final tabs = _tabs;
    final encodedTabs = jsonEncode(tabs);
    if (encodedTabs != _lastTabs) {
      _lastTabs = encodedTabs;
      _lastIndex = widget.selectedIndex;
      unawaited(_setTabs({...tabs, 'selectedIndex': widget.selectedIndex}));
    } else if (widget.selectedIndex != _lastIndex) {
      _lastIndex = widget.selectedIndex;
      unawaited(
        _channel.invokeMethod('setSelectedIndex', {
          'index': widget.selectedIndex,
        }),
      );
    }

    final isHidden = ModalRoute.isCurrentOf(context) != true;
    if (isHidden != _lastHidden) {
      _lastHidden = isHidden;
      unawaited(_channel.invokeMethod('setHidden', {'hidden': isHidden}));
    }
  }

  Future<void> _setTabs(Map<String, Object?> arguments) async {
    try {
      await _channel.invokeMethod('setTabs', arguments);
    } on PlatformException {
      // Sent again on the next rebuild instead of being treated as done.
      _lastTabs = null;
      rethrow;
    }
  }

  Map<String, Object?> get _tabs => {
    'items': [
      for (final (index, destination) in widget.destinations.indexed)
        {
          'id': '$index',
          'title': destination.label,
          'sfSymbol': extractSymbol(destination.icon),
          'selectedSfSymbol': extractSymbol(
            destination.selectedIcon ?? destination.icon,
          ),
          'assetName': extractAssetPath(destination.icon),
          'selectedAssetName': extractAssetPath(
            destination.selectedIcon ?? destination.icon,
          ),
          'filePath': extractFilePath(destination.icon),
          'networkUrl': extractNetworkUrl(destination.icon),
          'badge': _badgeOf(destination),
        },
    ],
    if (widget.action case final action?)
      'action': {
        'id': _actionId,
        'sfSymbol': action.sfSymbol,
        'title': action.label,
      },
  };

  /// Same badge as the iOS 26 tab bar: the text first, else a count capped at 99+.
  static String? _badgeOf(AdaptiveNavigationDestination destination) {
    final text = destination.badgeText;
    if (text != null && text.isNotEmpty) return text;
    final count = destination.badgeCount ?? 0;
    if (count <= 0) return null;
    return count > 99 ? '99+' : '$count';
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final arguments = call.arguments as Map?;
    switch (call.method) {
      case 'onTabSelected':
        final index = (arguments?['index'] as num?)?.toInt();
        if (index == null) return;
        // The native bar already shows this tab, so it is not sent back.
        _lastIndex = index;
        widget.onTap(index);
      case 'onAction':
        widget.action?.onPressed();
    }
  }
}
