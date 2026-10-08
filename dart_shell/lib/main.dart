import 'denial.dart';
import 'denial_default_shell.dart';
import 'src/settings/embedded_settings_surface.dart';
import 'src/local_apps/local_flutter_application.dart';

Future<void> main() async {
  await runDenialShell(
    shell: const DenialShellApp(),
    localApplications: (_) => <LocalFlutterApplication>[
      denialSettingsLocalApplication,
    ],
  );
}
