import 'package:flutter/widgets.dart';

// How a destination's icon reaches the native tab bars: by name, or as an
// image file, asset or URL. Each returns '' when the icon is another kind.

/// Extract SF Symbol name from an icon value.
/// Returns empty string for non-SF-Symbol icons (asset paths, IconData, widgets).
String extractSymbol(Object? icon) {
  if (icon is String && !icon.contains('/')) return icon;
  return '';
}

/// Extract asset path from an icon value.
/// Supports AssetImage, ImageIcon(AssetImage), and string paths containing '/'.
/// Returns empty string for SF Symbols or other icon types.
String extractAssetPath(Object? icon) {
  if (icon is AssetImage) return icon.assetName;
  if (icon is ImageIcon && icon.image is AssetImage) {
    return (icon.image as AssetImage).assetName;
  }
  if (icon is String && icon.contains('/')) return icon;
  return '';
}

String extractFilePath(Object? icon) {
  if (icon is FileImage) return icon.file.path;
  if (icon is ImageIcon && icon.image is FileImage) {
    return (icon.image as FileImage).file.path;
  }
  return '';
}

String extractNetworkUrl(Object? icon) {
  if (icon is NetworkImage) return icon.url;
  if (icon is ImageIcon && icon.image is NetworkImage) {
    return (icon.image as NetworkImage).url;
  }
  return '';
}
