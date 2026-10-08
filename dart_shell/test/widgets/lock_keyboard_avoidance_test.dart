import 'package:denial_dart_shell/src/settings/shell_settings.dart';
import 'package:denial_dart_shell/src/widgets/lock/lock_keyboard_avoidance.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Mi Pad 2 portrait docked keyboard keeps auth panel above keyboard', () {
    const size = Size(768, 1024);
    const safe = EdgeInsets.zero;

    final avoidance = resolveLockKeyboardAvoidance(
      viewSize: size,
      safePadding: safe,
      keyboardProgress: 1,
      tabletSettings: const ShellTabletSettings(
        oskLayoutMode: TabletOskLayoutMode.traditional,
      ),
    );

    // 32% docked keyboard starts at y=696.32. The lock panel content must end
    // at least 12 logical pixels above that edge.
    final safeBottom = size.height - 22 - avoidance.bottomInset;
    expect(safeBottom, closeTo(684.32, 0.1));
    expect(avoidance.topInset, 0);
    expect(avoidance.alignment, Alignment.bottomCenter);
  });

  test('floating keyboard chooses the larger free region on portrait lock', () {
    const size = Size(768, 1024);
    const safe = EdgeInsets.zero;

    final avoidance = resolveLockKeyboardAvoidance(
      viewSize: size,
      safePadding: safe,
      keyboardProgress: 1,
      tabletSettings: const ShellTabletSettings(
        oskLayoutMode: TabletOskLayoutMode.floating,
      ),
    );

    expect(avoidance.bottomInset, greaterThan(0));
    expect(avoidance.topInset, 0);
    expect(avoidance.alignment, Alignment.bottomCenter);
    expect(
      avoidance.availableHeight(viewSize: size, safePadding: safe),
      greaterThan(500),
    );
  });

  test('landscape lock does not move for keyboard avoidance', () {
    const size = Size(1024, 768);

    final avoidance = resolveLockKeyboardAvoidance(
      viewSize: size,
      safePadding: EdgeInsets.zero,
      keyboardProgress: 1,
      tabletSettings: const ShellTabletSettings(
        oskLayoutMode: TabletOskLayoutMode.traditional,
      ),
    );

    expect(avoidance.topInset, 0);
    expect(avoidance.bottomInset, 0);
  });
}
