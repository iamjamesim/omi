import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:omi/ui/omi_routes.dart';

const _channel = MethodChannel('com.omi/recording_detail_sheet');
int _nextSheet = 0;
_RecordingSheetRoute<dynamic>? _activeSheet;

/// UIKit supplies the sheet; the existing Flutter route supplies its live content.
/// A snapshot covers controller reparenting, without a second engine/provider tree.
Future<T?> showNativeRecordingSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, bool nativeSheet) builder,
}) async {
  final navigator = Navigator.of(context);
  final id = ++_nextSheet;
  var prepared = false;
  if (defaultTargetPlatform == TargetPlatform.iOS && _activeSheet == null) {
    try {
      prepared = await _channel.invokeMethod<bool>('prepare', {'id': id}) ?? false;
    } on MissingPluginException {
      // Older native builds keep their existing platform page route.
    } on PlatformException {
      // UIKit may already be presenting another controller.
    }
  }
  if (!context.mounted) {
    if (prepared) {
      await _channel.invokeMethod<void>('dismiss', {'id': id});
      await _channel.invokeMethod<void>('restored', {'id': id});
    }
    return null;
  }
  if (!prepared) return navigator.push<T>(omiPageRoute<T>(builder: (context) => builder(context, false)));

  final route = _RecordingSheetRoute<T>(id: id, builder: (context) => builder(context, true));
  _activeSheet = route;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'didDismiss' && (call.arguments as Map?)?['id'] == _activeSheet?.id) {
      _activeSheet?._didDismiss();
    }
  });
  final result = navigator.push<T>(route);
  try {
    // Build detail under the native cover, then let UIKit reveal it in the sheet.
    await WidgetsBinding.instance.endOfFrame;
    if (route.isActive && !route._nativeDismissed) await _channel.invokeMethod<void>('present', {'id': id});
  } on PlatformException {
    // A failed presentation restores Home and resolves the route, never strands the cover.
    await route._dismiss();
  }
  return result;
}

class _RecordingSheetRoute<T> extends PageRoute<T> {
  _RecordingSheetRoute({required this.id, required this.builder}) : super(fullscreenDialog: true);
  final int id;
  final WidgetBuilder builder;
  bool _nativeDismissed = false;
  bool _dismissRequested = false;
  bool _disposed = false;
  T? _result;

  @override
  Duration get transitionDuration => Duration.zero;
  @override
  bool get maintainState => true;
  @override
  Color? get barrierColor => null;
  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  bool didPop(T? result) {
    if (_nativeDismissed) return super.didPop(result);
    _result = result;
    unawaited(_dismiss());
    // Keep live detail painted throughout UIKit's dismiss/interactive transition.
    return false;
  }

  Future<void> _dismiss() async {
    if (_dismissRequested || _nativeDismissed) return;
    _dismissRequested = true;
    await _channel.invokeMethod<void>('dismiss', {'id': id});
  }

  void _didDismiss() {
    if (_nativeDismissed) return;
    _nativeDismissed = true;
    if (!_disposed && isCurrent) navigator?.pop<T>(_result);
    unawaited(_finishRestoration());
  }

  Future<void> _finishRestoration() async {
    // UIKit has dismissed the sheet but still holds its Home cover. Build Home
    // offscreen before reattaching Flutter; the native first-frame callback then
    // removes the cover only after the restored surface has actually rendered.
    WidgetsBinding.instance.scheduleWarmUpFrame();
    await WidgetsBinding.instance.endOfFrame;
    await _channel.invokeMethod<void>('restored', {'id': id});
    if (identical(_activeSheet, this)) _activeSheet = null;
  }

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    // A Flutter dialog/page inside the sheet must be closed first.
    if (!_nativeDismissed) {
      unawaited(_channel.invokeMethod<void>('setDismissible', {'id': id, 'enabled': nextRoute == null}));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_nativeDismissed) unawaited(_dismiss());
    super.dispose();
  }
}
