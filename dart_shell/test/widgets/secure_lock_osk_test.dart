import 'package:denial_dart_shell/src/widgets/lock/secure_lock_osk.dart';
import 'package:denial_dart_shell/src/widgets/osk/shell_osk_panel.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'touch keyboard edits the secure Flutter field without native events',
    () {
      final field = TextEditingController();
      addTearDown(field.dispose);
      var submits = 0;
      void send(ShellOskKeyIntent intent) {
        editSecureLockResponse(field, intent, onSubmit: () => submits++);
      }

      send(const ShellOskKeyIntent.text('hello'));
      send(const ShellOskKeyIntent.space());
      send(const ShellOskKeyIntent.text('🔒'));
      expect(field.text, 'hello 🔒');

      send(const ShellOskKeyIntent.backspace(phase: ShellOskKeyPhase.pressed));
      send(const ShellOskKeyIntent.backspace());
      send(const ShellOskKeyIntent.backspace(phase: ShellOskKeyPhase.released));
      expect(field.text, 'hello ');

      field.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      send(const ShellOskKeyIntent.text('PAM'));
      expect(field.text, 'PAM ');
      send(const ShellOskKeyIntent.enter());
      expect(submits, 1);
      expect(field.text, 'PAM ');
    },
  );

  test('secure text never accepts keyboard control/clipboard shortcuts', () {
    final field = TextEditingController(text: 'pw');
    addTearDown(field.dispose);
    editSecureLockResponse(
      field,
      const ShellOskKeyIntent.key('v', ctrl: true),
      onSubmit: () => fail('CTRL+V must not submit'),
    );
    editSecureLockResponse(
      field,
      const ShellOskKeyIntent.space(ctrl: true),
      onSubmit: () => fail('CTRL+Space must not submit'),
    );
    expect(field.text, 'pw');
  });

  test('secure input router drops callbacks when lock owner unmounts', () {
    final route = SecureLockOskRouter();
    final owner = Object();
    final unrelated = Object();
    var calls = 0;
    route.attach(owner, (intent) => calls++);
    route.dispatch(const ShellOskKeyIntent.text('x'));
    route.detach(unrelated);
    route.dispatch(const ShellOskKeyIntent.text('y'));
    route.detach(owner);
    route.dispatch(const ShellOskKeyIntent.text('z'));
    expect(calls, 2);
  });
}
