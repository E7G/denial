import 'package:flutter/widgets.dart';

/// A password editor may retain focus after the platform dismisses its IME.
/// Request the keyboard on every explicit pointer interaction, not only when
/// focus changes. A Listener does not compete with the editor's tap recognizers.
class LockKeyboardRequestRegion extends StatelessWidget {
  const LockKeyboardRequestRegion({
    super.key,
    required this.onRequestKeyboard,
    required this.child,
    this.enabled = true,
  });

  final VoidCallback onRequestKeyboard;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: enabled ? (_) => onRequestKeyboard() : null,
    child: child,
  );
}
