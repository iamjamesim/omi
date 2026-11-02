import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omi/ui/home_header_glass.dart';
import 'package:omi/widgets/header_circle_button.dart';
import 'package:omi/widgets/home_bottom_bar.dart';

void main() {
  testWidgets('native header has bounded toolbar height, measured 36pt materials, and working 44pt targets',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final ids = <int>[];
    final updates = <Map<dynamic, dynamic>>[];
    messenger.setMockMethodCallHandler(const MethodChannel('flutter/platform_views'), (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map;
        final id = args['id'] as int;
        ids.add(id);
        messenger.setMockMethodCallHandler(MethodChannel('com.omi/home_header_glass/$id'), (call) async {
          if (call.method == 'update') updates.add(call.arguments as Map);
          return null;
        });
      }
      return null;
    });
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(const MethodChannel('flutter/platform_views'), null);
      for (final id in ids) {
        messenger.setMockMethodCallHandler(MethodChannel('com.omi/home_header_glass/$id'), null);
      }
    });
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: HomeChatBarLayout(
            child: Scaffold(
      appBar: AppBar(
          title: HomeHeaderGlass(
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        HeaderCircleButton(icon: const Icon(Icons.search), semanticLabel: 'Search', onTap: () => taps++),
        HeaderCircleButton(icon: const Icon(Icons.settings), semanticLabel: 'Settings', onTap: () => taps++),
      ]))),
    ))));
    HomeChatBarLayout.updateNativeControls(tester.element(find.byType(HomeHeaderGlass)), true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(const ValueKey('home_native_header_glass'))).height, 44);
    expect(updates, isNotEmpty);
    final rects = updates.last['rects'] as List;
    expect(rects, hasLength(2));
    for (final rect in rects) {
      expect(rect['width'], 36);
      expect(rect['height'], 36);
    }
    expect(tester.getSize(find.byType(HeaderCircleButton).first), const Size(44, 44));
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pump();
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
