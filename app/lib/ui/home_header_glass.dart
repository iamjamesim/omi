import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:omi/ui/native_glass_overlay.dart';
import 'package:omi/ui/components/omi_icon_button.dart' show kOmiMinTapTarget;
import 'package:omi/widgets/home_bottom_bar.dart';

/// A single native material group beneath Home's existing Flutter header controls.
/// Buttons retain their actions, labels, badges, layouts and minimum touch targets.
class HomeHeaderGlass extends StatefulWidget {
  const HomeHeaderGlass({super.key, required this.child});
  final Widget child;
  @override
  State<HomeHeaderGlass> createState() => _HomeHeaderGlassState();
}

class _HomeHeaderGlassState extends State<HomeHeaderGlass> {
  final _root = GlobalKey();
  final _native = GlobalKey<_NativeHeaderGlassState>();
  late final _controller = _HeaderGlassController(_scheduleMeasure);
  List<Map<String, Object>> _rects = const [];
  bool _scheduled = false;
  bool _enabled = false;

  void _scheduleMeasure() {
    if (!mounted || !_enabled || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_enabled) return;
      final root = _root.currentContext?.findRenderObject();
      if (root is! RenderBox || !root.hasSize || !root.attached) return;
      final rects = <Map<String, Object>>[];
      for (final entry in _controller.targets.entries) {
        final box = entry.value.$1.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize || !box.attached) continue;
        final origin = box.localToGlobal(Offset.zero, ancestor: root);
        final rect = entry.value.$2.deflateRect(origin & box.size);
        if (rect.width <= 0 || rect.height <= 0) continue;
        rects.add(
            {'id': entry.key.toString(), 'x': rect.left, 'y': rect.top, 'width': rect.width, 'height': rect.height});
      }
      if (rects.toString() != _rects.toString()) setState(() => _rects = rects);
    });
  }

  @override
  Widget build(BuildContext context) {
    _enabled = defaultTargetPlatform == TargetPlatform.iOS && HomeChatBarLayout.nativeControlsOf(context);
    return _HeaderGlassScope(
        controller: _controller,
        enabled: _enabled,
        child: LayoutBuilder(builder: (context, _) {
          _scheduleMeasure();
          final header = Stack(key: _root, children: [
            if (_enabled) Positioned.fill(child: IgnorePointer(child: _NativeHeaderGlass(key: _native, rects: _rects))),
            widget.child,
          ]);
          return _enabled
              ? SizedBox(
                  height: kOmiMinTapTarget,
                  child: NativeGlassSnapshot(capture: () async => _native.currentState?.capture(), child: header))
              : header;
        }));
  }
}

class _HeaderGlassController {
  _HeaderGlassController(this.scheduleMeasure);
  final VoidCallback scheduleMeasure;
  final Map<int, (GlobalKey, EdgeInsets)> targets = {};
  void register(int id, GlobalKey key, EdgeInsets insets) {
    targets[id] = (key, insets);
    scheduleMeasure();
  }

  void remove(int id) {
    targets.remove(id);
    scheduleMeasure();
  }
}

class _HeaderGlassScope extends InheritedWidget {
  const _HeaderGlassScope({required this.controller, required this.enabled, required super.child});
  final _HeaderGlassController controller;
  final bool enabled;
  @override
  bool updateShouldNotify(_HeaderGlassScope oldWidget) =>
      enabled != oldWidget.enabled || controller != oldWidget.controller;
}

/// Marks only the painted capsule; the surrounding 44pt target stays Flutter-owned.
class HomeHeaderGlassTarget extends StatefulWidget {
  const HomeHeaderGlassTarget({super.key, required this.insets, required this.builder});
  final EdgeInsets insets;
  final Widget Function(bool glass) builder;
  @override
  State<HomeHeaderGlassTarget> createState() => _HomeHeaderGlassTargetState();
}

class _HomeHeaderGlassTargetState extends State<HomeHeaderGlassTarget> {
  static int _nextId = 0;
  final int _id = _nextId++;
  final _key = GlobalKey();
  _HeaderGlassController? _owner;
  @override
  void dispose() {
    _owner?.remove(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_HeaderGlassScope>();
    if (_owner != scope?.controller) {
      _owner?.remove(_id);
      _owner = scope?.controller;
    }
    _owner?.register(_id, _key, widget.insets);
    return SizedBox(key: _key, child: widget.builder(scope?.enabled ?? false));
  }
}

class _NativeHeaderGlass extends StatefulWidget {
  const _NativeHeaderGlass({super.key, required this.rects});
  final List<Map<String, Object>> rects;
  @override
  State<_NativeHeaderGlass> createState() => _NativeHeaderGlassState();
}

class _NativeHeaderGlassState extends State<_NativeHeaderGlass> {
  MethodChannel? _channel;
  Future<Uint8List?> capture() async => _channel?.invokeMethod<Uint8List>('snapshot');
  String? _last;
  Map<String, Object> _state() => {'rects': widget.rects, 'dark': Theme.of(context).brightness == Brightness.dark};
  void _update() {
    if (_channel == null) return;
    final state = _state();
    if (state.toString() == _last) return;
    _last = state.toString();
    unawaited(_channel!.invokeMethod<void>('update', state).catchError((Object _) {
      _last = null;
    }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(_NativeHeaderGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  Widget build(BuildContext context) => UiKitView(
        key: const ValueKey('home_native_header_glass'),
        viewType: 'omi/home_header_glass',
        creationParams: _state(),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          if (!mounted) return;
          _channel = MethodChannel('com.omi/home_header_glass/$id');
          _update();
        },
      );
}
