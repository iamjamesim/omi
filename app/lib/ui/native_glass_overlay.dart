import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Native backdrop effects must not be blurred a second time by a Flutter route.
/// Participants retain their live platform view offstage and paint a flat snapshot.
abstract interface class NativeGlassOverlayParticipant {
  Future<void> suspendGlass();
  void resumeGlass();
}

abstract final class NativeGlassOverlay {
  static final Set<NativeGlassOverlayParticipant> _participants = {};
  static int _covers = 0;
  static Future<void>? _preparing;

  static bool get isCovered => _covers > 0;

  static void register(NativeGlassOverlayParticipant participant) => _participants.add(participant);
  static void unregister(NativeGlassOverlayParticipant participant) => _participants.remove(participant);

  static Future<T?> push<T>(BuildContext context, TransitionRoute<T> route) {
    if (_participants.isEmpty) return Navigator.of(context).push<T>(route);
    return _pushPrepared(context, route);
  }

  static Future<T?> _pushPrepared<T>(BuildContext context, TransitionRoute<T> route) async {
    final first = _covers++ == 0;
    var released = false;
    Future<void> release() async {
      if (released) return;
      released = true;
      if (--_covers != 0) return;
      // completed removes the route; this frame removes its platform-view blur mutators.
      await WidgetsBinding.instance.endOfFrame;
      if (_covers != 0) return;
      for (final participant in _participants.toList()) {
        participant.resumeGlass();
      }
    }

    try {
      if (first) {
        _preparing = Future.wait(_participants.toList().map((p) => p.suspendGlass()));
      }
      await _preparing;
      // Commit the platform views offstage before the sheet's first backdrop frame.
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) {
        await release();
        return null;
      }
      final result = Navigator.of(context).push<T>(route);
      // popped resolves at the start of reverse; completed also covers drag cancellation.
      unawaited(route.completed.whenComplete(release));
      return await result;
    } catch (_) {
      await release();
      rethrow;
    }
  }
}

/// Keeps a native view alive without submitting it beneath Flutter's blur layers.
class NativeGlassSnapshot extends StatefulWidget {
  const NativeGlassSnapshot({super.key, required this.capture, required this.child});
  final Future<Uint8List?> Function() capture;
  final Widget child;
  @override
  State<NativeGlassSnapshot> createState() => _NativeGlassSnapshotState();
}

class _NativeGlassSnapshotState extends State<NativeGlassSnapshot> implements NativeGlassOverlayParticipant {
  bool _covered = NativeGlassOverlay.isCovered;
  ui.Image? _snapshot;
  @override
  void initState() {
    super.initState();
    NativeGlassOverlay.register(this);
  }

  @override
  Future<void> suspendGlass() async {
    if (_covered) return;
    ui.Image? snapshot;
    try {
      final bytes = await widget.capture();
      if (bytes != null && bytes.isNotEmpty) snapshot = await decodeImageFromList(bytes);
    } catch (_) {
      // Snapshot availability must never prevent the reader opening a sheet.
    }
    if (!mounted) {
      snapshot?.dispose();
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _covered = true;
    });
  }

  @override
  void resumeGlass() {
    if (!mounted) return;
    final previous = _snapshot;
    setState(() {
      _covered = false;
      _snapshot = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
  }

  @override
  void dispose() {
    NativeGlassOverlay.unregister(this);
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        if (_covered && _snapshot != null) RawImage(image: _snapshot, fit: BoxFit.fill),
        Offstage(offstage: _covered, child: widget.child),
      ]);
}
