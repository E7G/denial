import 'package:denial_dart_shell/src/input/input_layout.dart';
import 'package:denial_dart_shell/src/input/shell_interaction_registry.dart';
import 'package:denial_dart_shell/src/platform/denial_bridge.dart';
import 'package:denial_dart_shell/src/state/shell_input_layout_coordinator.dart';
import 'package:denial_dart_shell/src/state/shell_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('floating OSK publishes only its actual input region', () {
    final bridge = _InputBridge();
    final coordinator = ShellInputLayoutCoordinator(bridge);
    final state = ShellState.initial(
      locked: false,
    ).copyWith(edgePanelVisible: true);
    const floating = Rect.fromLTWH(286, 708, 470, 300);

    coordinator.publish(
      state: state,
      viewSize: const Size(768, 1024),
      interactions: const ShellInteractionSnapshot.empty(),
      floatingKeyboardRect: floating,
    );

    final snapshot = bridge.lastSnapshot;
    expect(snapshot, isNotNull);
    expect(snapshot!.softwareKeyboardRegions, const <Rect>[floating]);
    expect(
      snapshot.softwareKeyboardRegions,
      isNot(contains(const Rect.fromLTWH(0, 696, 768, 328))),
    );
  });
}

class _InputBridge extends DenialBridge {
  InputLayoutSnapshot? lastSnapshot;

  @override
  bool publishInputLayout(InputLayoutSnapshot snapshot) {
    lastSnapshot = snapshot;
    return true;
  }
}
