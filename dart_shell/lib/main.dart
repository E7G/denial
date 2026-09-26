import 'package:flutter/foundation.dart';

import 'denial.dart';
import 'denial_default_shell.dart';
import 'src/config/render_diagnostics.dart';

Future<void> main() async {
  if (desktopWindowsOnly) {
    debugPrint(
      'DENIAL_DIAGNOSTIC_WINDOWS_ONLY: stock desktop UI omitted; '
      'wallpaper ${desktopDiagnosticWallpaper ? 'retained' : 'omitted'}; '
      'Flutter window rendering, glass, cursor, and lock stage retained.',
    );
  }
  await runDenialShell(shell: const DenialShellApp());
}
