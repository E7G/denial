import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:denial_dart_shell/src/services/screenshot_file_monitor.dart';
import 'package:denial_dart_shell/src/widgets/screenshot_feedback_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mP8/x8AAwMCAO5+pO8AAAAASUVORK5CYII=',
);

void main() {
  test('Screenshot monitor fires only after the PNG is finished', () async {
    final directory = await Directory.systemTemp.createTemp(
      'denial-screenshot-monitor-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final saved = <String>[];
    final completed = Completer<void>();
    final monitor = ScreenshotFileMonitor(
      directory: directory,
      onSaved: (path) {
        saved.add(path);
        if (!completed.isCompleted) completed.complete();
      },
    );
    await monitor.start();
    addTearDown(monitor.dispose);

    final file = File('${directory.path}/Screenshot-1791526775-012.png');
    await file.writeAsBytes(_png.sublist(0, _png.length - 12), flush: true);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(saved, isEmpty);

    await file.writeAsBytes(_png, flush: true);
    await completed.future.timeout(const Duration(seconds: 5));
    expect(saved, <String>[file.path]);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    expect(saved, hasLength(1));
  });

  test('Truncated PNG does not pass the completion check', () async {
    final directory = await Directory.systemTemp.createTemp(
      'denial-screenshot-truncated-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/Screenshot-1791526775-123.png');
    await file.writeAsBytes(_png.sublist(0, _png.length - 12));
    expect(await ScreenshotFileMonitor.isFinishedPng(file), isFalse);
    await file.writeAsBytes(_png);
    expect(await ScreenshotFileMonitor.isFinishedPng(file), isTrue);
  });

  testWidgets('Saved screenshot shows Android-style card and auto dismisses', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final directory = Directory.systemTemp.createTempSync(
      'denial-screenshot-widget-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/Screenshot-1791526775-222.png');
    file.writeAsBytesSync(_png);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                ScreenshotFeedbackLayer(directory: directory),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('截图已保存'), findsNothing);
    container.read(screenshotFeedbackProvider.notifier).saved(file.path);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('截图已保存'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('screenshot-feedback-thumbnail')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 3900));
    await tester.pump(const Duration(milliseconds: 210));
    expect(find.text('截图已保存'), findsNothing);
  });

  testWidgets('Another screenshot restarts the card, and close dismisses', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync(
      'denial-screenshot-dismiss-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              ScreenshotFeedbackLayer(directory: directory),
            ],
          ),
        ),
      ),
    );
    container
        .read(screenshotFeedbackProvider.notifier)
        .saved('${directory.path}/Screenshot-1-001.png');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    container
        .read(screenshotFeedbackProvider.notifier)
        .saved('${directory.path}/Screenshot-2-002.png');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Screenshot saved'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('screenshot-feedback-dismiss')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Screenshot saved'), findsNothing);
  });
}
