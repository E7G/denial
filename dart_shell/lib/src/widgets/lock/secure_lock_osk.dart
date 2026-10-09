import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../osk/shell_osk_panel.dart';

/// Routes touch-keyboard actions exclusively to the active secure Flutter
/// password field while the native PAM session is locked.
///
/// No password data is stored here and the router never authenticates users.
/// The lock screen owns the text controller and hands its response to PAM.
class SecureLockOskRouter {
  Object? _owner;
  void Function(ShellOskKeyIntent)? _callback;

  void attach(Object owner, void Function(ShellOskKeyIntent) callback) {
    _owner = owner;
    _callback = callback;
  }

  void detach(Object owner) {
    if (identical(_owner, owner)) {
      _owner = null;
      _callback = null;
    }
  }

  void dispatch(ShellOskKeyIntent intent) {
    _callback?.call(intent);
  }
}

final secureLockOskRouterProvider = Provider<SecureLockOskRouter>((ref) {
  return SecureLockOskRouter();
});

/// Applies a touch-keyboard action to the lock's own EditableText without
/// involving native Wayland key delivery, clipboard, IME or application focus.
/// The field is still verified only by the existing PAM authentication flow.
void editSecureLockResponse(
  TextEditingController controller,
  ShellOskKeyIntent intent, {
  required VoidCallback onSubmit,
}) {
  if (intent.ctrl) return;
  if (intent.action == ShellOskKeyAction.enter) {
    onSubmit();
    return;
  }
  // ShellOskPanel emits down/tap/up for one backspace gesture. Apply only
  // the tap to avoid deleting two characters on a single touch.
  if (intent.action == ShellOskKeyAction.backspace &&
      intent.phase != ShellOskKeyPhase.tap) {
    return;
  }

  final value = controller.value;
  final text = value.text;
  final selection = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: text.length);
  var start = selection.start.clamp(0, text.length);
  final end = selection.end.clamp(0, text.length);
  final replacement = switch (intent.action) {
    ShellOskKeyAction.text => intent.text ?? '',
    ShellOskKeyAction.space => ' ',
    ShellOskKeyAction.backspace => '',
    _ => null,
  };
  if (replacement == null) return;
  if (intent.action == ShellOskKeyAction.backspace &&
      start == end &&
      start > 0) {
    // Backspace deletes a Unicode scalar, including surrogate pairs, rather
    // than accidentally producing an invalid UTF-16 password.
    final previous = text.substring(0, start).runes.last;
    start -= previous > 0xFFFF ? 2 : 1;
  }
  if (start == end &&
      intent.action == ShellOskKeyAction.backspace &&
      start == 0) {
    return;
  }
  final next = text.replaceRange(start, end, replacement);
  if (next.length > 1024) return;
  controller.value = TextEditingValue(
    text: next,
    selection: TextSelection.collapsed(offset: start + replacement.length),
  );
}
