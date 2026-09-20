import 'package:flutter/material.dart';

/// Captures one owned overlay route; unrelated routes are never traversed.
VoidCallback galleryOwnedOverlayExit(
  BuildContext context, {
  VoidCallback? onExit,
}) {
  final route = ModalRoute.of(context);
  final navigator = Navigator.of(context);
  var completed = false;
  return () {
    if (completed || route is! PopupRoute || !route.isActive) return;
    completed = true;
    navigator.removeRoute(route);
    onExit?.call();
  };
}
