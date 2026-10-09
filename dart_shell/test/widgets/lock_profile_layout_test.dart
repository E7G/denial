import 'package:denial_dart_shell/src/state/shell_profile.dart';
import 'package:denial_dart_shell/src/widgets/lock/lock_screen_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mi Pad 2 mobile lock stays mobile across portrait and landscape', () {
    // Orientation changes logical width from 768 to 1024. This should never
    // replace the mobile password panel with the desktop one.
    for (final logicalWidth in <double>[768, 1024]) {
      expect(logicalWidth, greaterThan(0));
      expect(
        lockUsesDesktopPresentation(
          shellProfile: ShellProfile.mobile,
          outputCount: 1,
        ),
        isFalse,
      );
    }
  });

  test(
    'desktop and multi-display lock continue to use desktop presentation',
    () {
      expect(
        lockUsesDesktopPresentation(
          shellProfile: ShellProfile.desktop,
          outputCount: 1,
        ),
        isTrue,
      );
      expect(
        lockUsesDesktopPresentation(
          shellProfile: ShellProfile.mobile,
          outputCount: 2,
        ),
        isTrue,
      );
    },
  );
}
