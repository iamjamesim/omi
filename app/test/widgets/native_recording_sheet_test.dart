import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omi/ui/navigation/native_recording_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.omi/recording_detail_sheet');
  const codec = StandardMethodCodec();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  int? id;
  var supported = true;

  Future<void> nativeDismissed({int? sheetId}) async {
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall('didDismiss', {'id': sheetId ?? id})),
      (_) {},
    );
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    id = null;
    supported = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'prepare') {
        id = (call.arguments as Map)['id'] as int;
        return supported;
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showNativeRecordingSheet<void>(
                context,
                builder: (context, native) => Scaffold(
                  body: Column(
                    children: [
                      Text(native ? 'Native detail' : 'Page detail'),
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close detail')),
                    ],
                  ),
                ),
              ),
              child: const Text('Home recording'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Home recording'));
    await tester.pumpAndSettle();
  }

  testWidgets('close keeps live detail until native dismiss finishes, then restores Home', (tester) async {
    await open(tester);
    expect(find.text('Native detail'), findsOneWidget);
    expect(calls.where((c) => c.method == 'present'), hasLength(1));
    await tester.tap(find.text('Close detail'));
    await tester.pump();
    expect(find.text('Native detail'), findsOneWidget);
    expect(calls.where((c) => c.method == 'dismiss'), hasLength(1));
    await nativeDismissed();
    await tester.pumpAndSettle();
    expect(find.text('Home recording'), findsOneWidget);
    expect(calls.where((c) => c.method == 'restored'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('native swipe dismissal pops only the recording detail and can reopen', (tester) async {
    await open(tester);
    await nativeDismissed();
    await tester.pumpAndSettle();
    expect(find.text('Home recording'), findsOneWidget);
    await tester.tap(find.text('Home recording'));
    await tester.pumpAndSettle();
    expect(find.text('Native detail'), findsOneWidget);
    expect(calls.where((c) => c.method == 'present'), hasLength(2));
    await nativeDismissed();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('late dismissal from an older sheet cannot close a reopened detail', (tester) async {
    await open(tester);
    final previousId = id;
    await nativeDismissed();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home recording'));
    await tester.pumpAndSettle();
    expect(id, isNot(previousId));
    await nativeDismissed(sheetId: previousId);
    await tester.pumpAndSettle();
    expect(find.text('Native detail'), findsOneWidget);
    expect(calls.where((c) => c.method == 'restored'), hasLength(1));
    await nativeDismissed();
    await tester.pumpAndSettle();
    expect(find.text('Home recording'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('unavailable native host keeps ordinary navigation and never leaves a cover', (tester) async {
    supported = false;
    await open(tester);
    expect(find.text('Page detail'), findsOneWidget);
    expect(calls.where((c) => c.method == 'present'), isEmpty);
    await tester.tap(find.text('Close detail'));
    await tester.pumpAndSettle();
    expect(find.text('Home recording'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
