import 'package:flutter/material.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:omi/ui/omi_tokens.dart';
import 'package:omi/utils/l10n_extensions.dart';

/// The two-bubbles glyph (FontAwesome `comments`, regular weight) that marks Ask Omi everywhere it
/// appears, so every entry point reads as one family.
const FaIconData kAskOmiGlyph = FontAwesomeIcons.comments;

/// The Home shell has no tab bar: Home and Tasks are switched at the top of the screen, and the only
/// thing at the bottom is Home's floating [Ask Omi | record] row. These helpers are the one source
/// of the space that row and the system inset take, so nothing positions itself with a literal.

/// Height of the fade that dissolves list content just above the chat bar. Paint only.
const double kHomeBottomFadeHeight = 20;

/// Gap between the chat bar and the system inset (or the screen edge when there is none).
const double kHomeChatBarBottomGap = 8;

/// Height of Home's floating chat bar.
const double kHomeChatBarHeight = 62;

/// Space every Home-shell page leaves below its last row so it can scroll clear of the screen edge.
const double kHomeScrollEndPadding = 24;

/// The bottom inset the shell reserves for system chrome.
///
/// viewPadding, not padding: the home Scaffold sets resizeToAvoidBottomInset: false, and
/// padding.bottom collapses to zero while a keyboard is open.
double homeBottomInset(BuildContext context) => MediaQuery.viewPaddingOf(context).bottom;

/// Distance from the bottom of the screen that a Home-shell page without the chat bar (Tasks)
/// clears: the system inset plus a little air.
double homeBottomClearance(BuildContext context) => homeBottomInset(context) + kHomeScrollEndPadding;

/// Offset from the bottom of the screen to the bottom edge of Home's chat bar.
double homeChatBarOffset(BuildContext context) => homeBottomInset(context) + kHomeChatBarBottomGap;

/// Distance from the bottom of the screen that Home content clears to stay out from under the
/// floating chat bar, with a little air above it.
double homeChatBarClearance(BuildContext context) =>
    homeChatBarOffset(context) + HomeChatBarLayout.heightOf(context) + kHomeBottomFadeHeight;

/// Home-scoped measured bar geometry; list padding follows native Dynamic Type
/// and localization changes without coupling layout to capture authority.
class HomeChatBarLayout extends StatefulWidget {
  const HomeChatBarLayout({super.key, required this.child});
  final Widget child;

  static double heightOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HomeChatBarHeight>()?.notifier?.value ?? kHomeChatBarHeight;

  /// The native pill replaces Home's streaming status row once available.
  static bool nativeControlsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HomeNativeCaptureControls>()?.notifier?.value ?? false;

  static void updateNativeControls(BuildContext context, bool enabled) {
    final native = context.getInheritedWidgetOfExactType<_HomeNativeCaptureControls>()?.notifier;
    if (native != null && native.value != enabled) native.value = enabled;
  }

  static void updateHeight(BuildContext context, double height) {
    final metrics = context.getInheritedWidgetOfExactType<_HomeChatBarHeight>()?.notifier;
    if (metrics != null && (metrics.value - height).abs() > 0.5) metrics.value = height;
  }

  @override
  State<HomeChatBarLayout> createState() => _HomeChatBarLayoutState();
}

class _HomeChatBarLayoutState extends State<HomeChatBarLayout> {
  final _height = ValueNotifier<double>(kHomeChatBarHeight);
  final _nativeControls = ValueNotifier<bool>(false);
  @override
  void dispose() {
    _height.dispose();
    _nativeControls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _HomeNativeCaptureControls(
        notifier: _nativeControls,
        child: _HomeChatBarHeight(notifier: _height, child: widget.child),
      );
}

class _HomeNativeCaptureControls extends InheritedNotifier<ValueNotifier<bool>> {
  const _HomeNativeCaptureControls({required super.notifier, required super.child});
}

class _HomeChatBarHeight extends InheritedNotifier<ValueNotifier<double>> {
  const _HomeChatBarHeight({required super.notifier, required super.child});
}

/// Interpolate the light fade through transparent page-coloured pixels. A zero-alpha black stop
/// darkens intermediate gradient colours and shows up as a grey band against the light page.
Color get _fadeStart =>
    OmiColors.active == OmiPalette.light ? OmiColors.surface0.withValues(alpha: 0) : Colors.transparent;

/// The backdrop behind Home's floating [Ask Omi | record] row: solid page colour from the screen
/// edge up through the row, fading out above it, so list content never shows between the chat bar
/// and the record button or around them. Paint only; a [Stack] child placed before the row.
class HomeChatBarBackdrop extends StatelessWidget {
  const HomeChatBarBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final solid = homeChatBarOffset(context) + kHomeChatBarHeight;
    final height = solid + kHomeBottomFadeHeight;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, kHomeBottomFadeHeight / height, 1.0],
              colors: [_fadeStart, OmiColors.surface0, OmiColors.surface0],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centred "Ask anything" button in Home's bottom bar (#19854).
class HomeAskAnythingButton extends StatelessWidget {
  final VoidCallback? onTap;

  const HomeAskAnythingButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.askAnything;
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: GestureDetector(
        key: const ValueKey('home_ask_omi_bar'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: kHomeChatBarHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: OmiColors.surface1,
            borderRadius: OmiRadius.pillAll,
            border: Border.all(color: OmiColors.border, width: 1),
          ),
          child: Text(
            label,
            style: OmiType.subhead.copyWith(
              color: OmiColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
