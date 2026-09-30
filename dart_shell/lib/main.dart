import 'package:denial_clock/denial_clock.dart';
import 'package:denial_desktop/denial_desktop.dart';
import 'package:denial_flutter_sdk/shell.dart';
import 'package:denial_taskbar/denial_taskbar.dart';
import 'package:denial_launcher/denial_launcher.dart';

Future<void> main() async {
  await runDenialShell(
    shell: const ReferenceDesktop(
      surfaces: [TaskbarPlugin(), DesktopClockPlugin()],
      workArea: TaskbarWorkArea(),
      launcher: LauncherPlugin(),
      actions: [OpenApplicationsAction()],
    ).createShell(),
  );
}
