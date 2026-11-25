import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'platform_info.dart';

/// The room UIKit gives a vertical bar on each side of the window
/// (`UIView.edgeInsets(for: .bar(onEdge:extent:))`, iOS 27.1). UIKit keeps it
/// clear of the camera, the Dynamic Island and the status cluster.
@immutable
class SystemStripInsets {
  const SystemStripInsets({
    required this.windowSize,
    required this.safeLeft,
    required this.safeRight,
    required this.left,
    required this.right,
  });

  final Size windowSize;
  final double safeLeft;
  final double safeRight;
  final ({double top, double bottom}) left;
  final ({double top, double bottom}) right;

  /// False for a reading from before a rotation, fold or pane move. A half
  /// turn keeps the size, so the side insets have to match too.
  bool matches(Size size, EdgeInsets viewPadding) =>
      _isSame(windowSize.width, size.width) &&
      _isSame(windowSize.height, size.height) &&
      _isSame(safeLeft, viewPadding.left) &&
      _isSame(safeRight, viewPadding.right);

  // Flutter's values went through physical pixels, so they can be a fraction off.
  static bool _isSame(double a, double b) => (a - b).abs() < 0.5;

  /// Null for anything but a full reading, such as "unsupported" below iOS 27.1.
  static SystemStripInsets? fromWire(Object? message) => switch (message) {
    {
      'width': final double width,
      'height': final double height,
      'safeLeft': final double safeLeft,
      'safeRight': final double safeRight,
      'leftTop': final double leftTop,
      'leftBottom': final double leftBottom,
      'rightTop': final double rightTop,
      'rightBottom': final double rightBottom,
    } =>
      SystemStripInsets(
        windowSize: Size(width, height),
        safeLeft: safeLeft,
        safeRight: safeRight,
        left: (top: leftTop, bottom: leftBottom),
        right: (top: rightTop, bottom: rightBottom),
      ),
    _ => null,
  };

  static const EventChannel _channel = EventChannel(
    'adaptive_platform_ui/strip_insets',
  );
  static final ValueNotifier<SystemStripInsets?> _latest = ValueNotifier(null);
  static StreamSubscription<Object?>? _sub;

  /// The latest reading, null until the first one and where the system has none.
  static ValueListenable<SystemStripInsets?> get latest {
    if (PlatformInfo.isIOS26OrHigher()) {
      _sub ??= _channel.receiveBroadcastStream().listen(
        (message) => _latest.value = fromWire(message),
        onError: (Object _) {},
      );
    }
    return _latest;
  }
}
