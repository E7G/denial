import 'package:denial_dart_shell/src/widgets/lock/lock_keyboard_request_region.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('retapping a focused password field requests the keyboard again', (
    tester,
  ) async {
    final focus = FocusNode();
    final text = TextEditingController();
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LockKeyboardRequestRegion(
            onRequestKeyboard: () => requests++,
            child: TextField(
              focusNode: focus,
              controller: text,
              obscureText: true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    final first = requests;
    expect(first, 1);
    tester.testTextInput.hide();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    expect(requests, first + 1);
    await tester.pumpWidget(const SizedBox.shrink());
    focus.dispose();
    text.dispose();
  });

  testWidgets('disabled response region never requests a keyboard', (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LockKeyboardRequestRegion(
          enabled: false,
          onRequestKeyboard: () => requests++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.tapAt(const Offset(20, 20));
    expect(requests, 0);
  });
}
