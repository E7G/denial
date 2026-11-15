import 'package:denial_dart_shell/src/core/shell_overlay_host.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/mobile_motion_harness.dart';

void main() {
  testWidgets(
    'root overlay releases its scene after the entry widget unmounts',
    (tester) async {
      for (var cycle = 0; cycle < 3; cycle++) {
        await tester.pumpWidget(
          mobileMotionHarness(const ShellOverlayHost(child: Text('scene'))),
        );
        expect(find.text('scene'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'scene updates keep one stable root overlay and dispose cleanly',
    (tester) async {
      Widget frame(String label) =>
          mobileMotionHarness(ShellOverlayHost(child: Text(label)));
      await tester.pumpWidget(frame('before'));
      final overlay = tester.state<OverlayState>(find.byType(Overlay));
      await tester.pumpWidget(frame('after'));
      await tester.pump();
      expect(tester.state<OverlayState>(find.byType(Overlay)), same(overlay));
      expect(find.text('before'), findsNothing);
      expect(find.text('after'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
