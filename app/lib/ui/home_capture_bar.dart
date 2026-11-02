import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:omi/pages/home/widgets/battery_info_widget.dart';
import 'package:omi/providers/capture_provider.dart';
import 'package:omi/services/capture/capture_system_surface.dart';
import 'package:omi/ui/ui.dart';
import 'package:omi/ui/native_glass_overlay.dart';
import 'package:omi/utils/enums.dart';
import 'package:omi/utils/l10n_extensions.dart';
import 'package:omi/widgets/home_bottom_bar.dart';

/// Home's native iOS 26 control, backed by the same projection as the Live Activity.
/// Other platforms keep the existing Flutter presentation and recording actions.
class HomeCaptureBar extends StatefulWidget {
  const HomeCaptureBar({
    super.key,
    required this.onAsk,
    required this.onRecordingDetails,
  });

  final VoidCallback onAsk;
  final Future<void> Function() onRecordingDetails;

  @override
  State<HomeCaptureBar> createState() => _HomeCaptureBarState();
}

class _HomeCaptureBarState extends State<HomeCaptureBar> {
  static const _capabilities = MethodChannel('com.omi/home_capture_controls');
  bool _supported = false;
  double _height = 64;

  @override
  void initState() {
    super.initState();
    unawaited(_checkSupport());
  }

  Future<void> _checkSupport() async {
    if (!Platform.isIOS) return;
    try {
      final supported = await _capabilities.invokeMethod<bool>('isSupported') ?? false;
      if (mounted) {
        setState(() => _supported = supported);
        HomeChatBarLayout.updateNativeControls(
          context,
          supported && context.read<CaptureProvider>().homeControls != null,
        );
        if (supported && context.read<CaptureProvider>().homeControls != null) {
          HomeChatBarLayout.updateHeight(context, _height);
        }
      }
    } on MissingPluginException {
      // Older native builds retain the Flutter control.
    } on PlatformException {
      // A capability probe has no effect on capture.
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = context.read<CaptureProvider>().homeControls;
    final native = _supported && surface != null;
    return Stack(
      children: [
        if (!native) const HomeChatBarBackdrop(),
        Positioned(
          left: native ? 20 : 16,
          right: native ? 20 : 16,
          bottom: homeChatBarOffset(context),
          child: native
              ? HomeRecordButton(
                  openDetailsOnStart: false,
                  presentation: (start, options, didFinish) => SizedBox(
                    height: _height,
                    child: _NativeHomeCaptureBar(
                      surface: surface,
                      onAsk: widget.onAsk,
                      onRecordingDetails: widget.onRecordingDetails,
                      onStart: start,
                      onFinish: didFinish,
                      onOptions: options,
                      onHeight: (height) {
                        if (!mounted) return;
                        if ((_height - height).abs() > 0.5) setState(() => _height = height);
                        HomeChatBarLayout.updateHeight(context, height);
                      },
                    ),
                  ),
                )
              : Row(
                  children: [
                    Expanded(child: HomeAskAnythingButton(onTap: widget.onAsk)),
                    const SizedBox(width: 10),
                    const HomeRecordButton(),
                  ],
                ),
        ),
      ],
    );
  }
}

class _NativeHomeCaptureBar extends StatefulWidget {
  const _NativeHomeCaptureBar({
    required this.surface,
    required this.onAsk,
    required this.onRecordingDetails,
    required this.onStart,
    required this.onFinish,
    required this.onOptions,
    required this.onHeight,
  });

  final CaptureSystemSurface surface;
  final VoidCallback onAsk;
  final Future<void> Function() onRecordingDetails;
  final Future<void> Function() onStart;
  final VoidCallback onFinish;
  final VoidCallback? onOptions;
  final ValueChanged<double> onHeight;

  @override
  State<_NativeHomeCaptureBar> createState() => _NativeHomeCaptureBarState();
}

class _NativeHomeCaptureBarState extends State<_NativeHomeCaptureBar> {
  // Own touches immediately; Home's outer unfocus tap must not win this arena.
  static final _gestures = <Factory<OneSequenceGestureRecognizer>>{
    const Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
  };
  MethodChannel? _channel;
  bool _busy = false;
  double _recordButtonExtent = 64;
  final _loadingExtent = ValueNotifier<double?>(null);
  bool _openingDetails = false;
  String? _lastPayload;

  @override
  void initState() {
    super.initState();
    // omi-perf-allow: unselected-provider-listener -- state-only projection; _update skips unchanged selected payloads
    widget.surface.addListener(_update);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(_NativeHomeCaptureBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surface != widget.surface) {
      oldWidget.surface.removeListener(_update);
      // omi-perf-allow: unselected-provider-listener -- state-only bridge; _update returns on an unchanged selected payload
      widget.surface.addListener(_update);
      _lastPayload = null;
    }
    _update();
  }

  Map<String, Object?> _state() {
    final capture = context.read<CaptureProvider>();
    final l10n = context.l10n;
    final snapshot = widget.surface.snapshot;
    return {
      ...snapshot,
      'busy': _busy || snapshot['busy'] == true || capture.recordingState == RecordingState.initialising,
      'canShowOptions': widget.onOptions != null,
      'canOpenDetails':
          snapshot['active'] == true && snapshot['source'] == 'phone' && !capture.isPhoneMicBatchRecording,
      'dark': Theme.of(context).brightness == Brightness.dark,
      'labels': {
        'ask': l10n.askAnything,
        'record': l10n.startRecording,
        'pause': l10n.pauseRecording,
        'resume': l10n.resumeRecording,
        'recording': l10n.recording,
        'paused': l10n.recordingPaused,
        'details': l10n.recordingDetails,
        'detailsHint': l10n.viewTranscript,
        // The existing localized short End label is also used by the call button.
        'end': l10n.phoneEndCall,
        'endAccessibility': l10n.stopRecording,
        'options': l10n.moreWaysToRecord,
      },
    };
  }

  void _update() {
    if (!mounted) return;
    final value = _state();
    final phoneActive = value['active'] == true && value['source'] == 'phone';
    _loadingExtent.value = value['busy'] == true && !phoneActive ? _recordButtonExtent : null;
    if (_channel == null) return;
    final selected = {...value};
    if (selected['paused'] != true) selected.remove('elapsed');
    final fingerprint = selected.toString();
    if (fingerprint == _lastPayload) return;
    _lastPayload = fingerprint;
    unawaited(
      _channel!.invokeMethod<void>('update', value).catchError((Object _) {
        _lastPayload = null;
        // A platform view can detach while a queued capture notification is delivered.
      }),
    );
  }

  Future<Object?> _handle(MethodCall call) async {
    if (!mounted) return null;
    final args = Map<String, Object?>.from(call.arguments as Map? ?? const {});
    if (call.method == 'height') {
      final extent = args['recordButtonExtent'];
      if (extent is num && extent.isFinite && extent >= 64 && extent <= 600) {
        _recordButtonExtent = extent.toDouble();
        _update();
      }
      final height = args['height'];
      if (height is num && height.isFinite && height >= 64 && height <= 1200) {
        widget.onHeight(height.toDouble());
      }
      return null;
    }
    if (call.method != 'action') throw MissingPluginException();
    final action = args['action'];
    if (action == 'ask') {
      widget.onAsk();
      return null;
    }
    if (action == 'details') {
      if (_openingDetails || _busy) return null;
      final current = _state();
      // A delayed tap must not open another recording after capture changes.
      if (current['canOpenDetails'] != true ||
          args['recordingId'] != current['recordingId'] ||
          args['conversationRevision'] != current['conversationRevision']) {
        return null;
      }
      _openingDetails = true;
      try {
        await widget.onRecordingDetails();
      } finally {
        _openingDetails = false;
      }
      return null;
    }
    if (action == 'options') {
      widget.onOptions?.call();
      return null;
    }
    if (_busy) return null;
    _busy = true;
    _update();
    try {
      if (action == 'record') {
        // A queued idle tap must never toggle/finish a recording started elsewhere.
        final capture = context.read<CaptureProvider>();
        final current = widget.surface.snapshot;
        if (capture.liveCaptureSource == 'phone' ||
            args['recordingId'] != current['recordingId'] ||
            args['conversationRevision'] != current['conversationRevision']) {
          return null;
        }
        await widget.onStart();
      } else {
        await widget.surface.performAction(args);
        if (action == 'finish') widget.onFinish();
      }
    } catch (_) {
      if (mounted) OmiFeedback.error(context, context.l10n.somethingWentWrong);
    } finally {
      _busy = false;
      _update();
    }
    return mounted ? _state() : null;
  }

  @override
  void dispose() {
    widget.surface.removeListener(_update);
    _channel?.setMethodCallHandler(null);
    _loadingExtent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NativeGlassSnapshot(
        capture: () async => _channel?.invokeMethod<Uint8List>('snapshot'),
        child: Stack(
          children: [
            UiKitView(
              key: const ValueKey('home_native_capture_controls'),
              viewType: 'omi/home_capture_controls',
              gestureRecognizers: _gestures,
              creationParams: _state(),
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: (id) {
                if (!mounted) return;
                _channel = MethodChannel('com.omi/home_capture_controls/$id')..setMethodCallHandler(_handle);
                _update();
              },
            ),
            // Keep Omi's actual activity indicator, including its motion and tokens.
            // Native layout reports the target extent so this also follows Dynamic Type.
            ValueListenableBuilder<double?>(
              valueListenable: _loadingExtent,
              builder: (context, extent, _) => extent == null
                  ? const SizedBox.shrink()
                  : Positioned(
                      right: 0,
                      bottom: 0,
                      width: extent,
                      height: extent,
                      child: const IgnorePointer(
                        child: ExcludeSemantics(
                          child: Center(
                            child: OmiSpinner(size: OmiSpinnerSize.small),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      );
}
