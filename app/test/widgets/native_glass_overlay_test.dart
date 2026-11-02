import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omi/pages/chat/chat_route.dart';
import 'package:omi/pages/search/global_search.dart';
import 'package:omi/ui/native_glass_overlay.dart';

class _Glass implements NativeGlassOverlayParticipant {
  int snapshots = 0;
  int restores = 0;
  Future<void>? captureGate;
  @override
  Future<void> suspendGlass() async {
    snapshots++;
    await captureGate;
  }

  @override
  void resumeGlass() => restores++;
}

void main() {
  for (final search in [false, true]) {
    testWidgets(
        '${search ? 'search' : 'chat'} captures before the first backdrop frame and restores after reverse completes',
        (tester) async {
      final glass = _Glass();
      final gate = Completer<void>();
      glass.captureGate = gate.future;
      NativeGlassOverlay.register(glass);
      addTearDown(() => NativeGlassOverlay.unregister(glass));
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
          navigatorKey: nav,
          home: Builder(
              builder: (context) => TextButton(
                    onPressed: () => NativeGlassOverlay.push(
                        context,
                        search
                            ? SearchDropRoute<void>(builder: (_) => const Text('chat'))
                            : ChatSheetRoute<void>(builder: (_) => const Text('chat'))),
                    child: const Text('open'),
                  ))));
      await tester.tap(find.text('open'));
      await tester.pump();
      expect(glass.snapshots, 1);
      expect(find.text('chat'), findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('chat'), findsOneWidget);
      nav.currentState!.pop();
      await tester.pump();
      expect(glass.restores, 0, reason: 'pop resolves before the reverse transition');
      await tester.pump(const Duration(milliseconds: 140));
      expect(glass.restores, 0);
      await tester.pumpAndSettle();
      expect(glass.restores, 1);
      expect(NativeGlassOverlay.isCovered, isFalse);
    });
  }

  testWidgets('a cancelled dismiss drag retains the snapshot until the sheet actually closes', (tester) async {
    final glass = _Glass();
    NativeGlassOverlay.register(glass);
    addTearDown(() => NativeGlassOverlay.unregister(glass));
    final nav = GlobalKey<NavigatorState>();
    late ChatSheetRoute<void> route;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () {
                    route = ChatSheetRoute<void>(builder: (_) => const Text('chat'));
                    NativeGlassOverlay.push(context, route);
                  },
                  child: const Text('open'),
                ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(route.startDismissDrag(extent: 600, reduceMotion: false), isTrue);
    route.updateDismissDrag(150);
    await tester.pump();
    route.finishDismissDrag(0, cancelled: true);
    await tester.pumpAndSettle();
    expect(glass.snapshots, 1);
    expect(glass.restores, 0);
    expect(NativeGlassOverlay.isCovered, isTrue);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(glass.restores, 1);
  });

  testWidgets('nested sheets keep native glass suspended until the final sheet closes', (tester) async {
    final glass = _Glass();
    NativeGlassOverlay.register(glass);
    addTearDown(() => NativeGlassOverlay.unregister(glass));
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () => NativeGlassOverlay.push(
                      context,
                      ChatSheetRoute<void>(
                          builder: (context) => TextButton(
                                onPressed: () => NativeGlassOverlay.push(
                                    context, ChatSheetRoute<void>(builder: (_) => const Text('second'))),
                                child: const Text('next'),
                              ))),
                  child: const Text('open'),
                ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    expect(glass.snapshots, 1);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(glass.restores, 0);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(glass.restores, 1);
    expect(NativeGlassOverlay.isCovered, isFalse);
  });
}
