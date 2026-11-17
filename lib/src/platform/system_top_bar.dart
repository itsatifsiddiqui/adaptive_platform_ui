import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Where the system puts a top bar in this window, as the bar's top in points
/// (`UIView.edgeInsets(for: .bar(onEdge: .top))`, iOS 27.1). Null before the
/// first reading and below iOS 27.1, where the safe area top is used instead.
///
/// On the open iPhone Duo in portrait it is above the safe area, so the bar
/// shares the status island's row like the system's own bars.
abstract final class SystemTopBar {
  static const EventChannel _channel = EventChannel('adaptive_platform_ui/top_bar');
  static final ValueNotifier<double?> _top = ValueNotifier(null);
  static StreamSubscription<Object?>? _sub;

  static ValueListenable<double?> get top {
    _sub ??= _channel.receiveBroadcastStream().listen(
      (value) => _top.value = value is num ? value.toDouble() : null,
      onError: (Object _) {},
    );
    return _top;
  }
}

/// The top bar position the host decided, for the pages below it.
class TopBarScope extends InheritedWidget {
  const TopBarScope({super.key, required this.top, required super.child});

  /// Null where the bar sits at the safe area top.
  final double? top;

  static double? maybeTopOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TopBarScope>()?.top;

  @override
  bool updateShouldNotify(TopBarScope oldWidget) => top != oldWidget.top;
}
