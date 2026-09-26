import 'dart:io';

import 'package:denial_dart_shell/src/launcher/repositories/desktop_apps_repository.dart';
import 'package:denial_dart_shell/src/launcher/runtime_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late Directory dataDirectory;
  late DesktopAppsRepository repository;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'denial-app-icons-',
    );
    dataDirectory = Directory(p.join(temporaryDirectory.path, 'share'))
      ..createSync(recursive: true);
    repository = DesktopAppsRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': p.join(temporaryDirectory.path, 'home'),
          'XDG_DATA_HOME': dataDirectory.path,
          'XDG_DATA_DIRS': '',
        },
      ),
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  test('resolves file URIs and declared symbolic icon directories', () {
    final directIcon = _writeFile(
      temporaryDirectory,
      'direct/icon.svg',
      '<svg/>',
    );
    expect(
      repository.resolveIconPath(directIcon.uri.toString()),
      directIcon.path,
    );

    final theme = Directory(p.join(dataDirectory.path, 'icons', 'Fixture'))
      ..createSync(recursive: true);
    _writeFile(
      theme,
      'index.theme',
      '[Icon Theme]\n'
          'Name=Fixture\n'
          'Directories=symbolic/status\n',
    );
    final batteryIcon = _writeFile(
      theme,
      'symbolic/status/battery-caution-symbolic.svg',
      '<svg/>',
    );

    expect(
      repository.resolveIconPath('battery-caution-symbolic'),
      batteryIcon.path,
    );
  });

  test('uses the desktop entry icon when the app icon is omitted', () {
    final appIcon = _writeFile(
      dataDirectory,
      'icons/hicolor/128x128/apps/org.example.Chat.svg',
      '<svg/>',
    );
    _writeFile(
      dataDirectory,
      'applications/org.example.Chat.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Example Chat\n'
          'Icon=org.example.Chat\n',
    );

    expect(
      repository.resolveNotificationIcon(
        appIcon: '',
        desktopEntry: 'org.example.Chat',
        appName: '',
      ),
      appIcon.path,
    );
  });

  test('falls back to matching app metadata when clients omit icon hints', () {
    final appIcon = _writeFile(
      dataDirectory,
      'icons/hicolor/128x128/apps/org.example.Chat.svg',
      '<svg/>',
    );
    _writeFile(
      dataDirectory,
      'applications/org.example.Chat.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Example Chat\n'
          'StartupWMClass=ExampleChat\n'
          'Icon=org.example.Chat\n',
    );

    expect(
      repository.resolveNotificationIcon(
        appIcon: '',
        desktopEntry: '',
        appName: 'Example Chat',
      ),
      appIcon.path,
    );
  });

  test('loads desktop-entry keywords into launcher search metadata', () async {
    _writeFile(
      dataDirectory,
      'applications/auto-caption.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Auto Caption\n'
          'Exec=/usr/bin/auto-caption\n'
          'Categories=Utility;AudioVideo;\n'
          r'Keywords=subtitle;live\sstream;caption\;overlay;'
          '\n',
    );

    final applications = await repository.loadApplications();
    final application = applications.singleWhere(
      (app) => app.id == 'auto-caption.desktop',
    );

    expect(application.keywords, const <String>[
      'subtitle',
      'live stream',
      'caption;overlay',
    ]);
    expect(application.searchableText, contains('subtitle'));
    expect(application.searchableText, contains('live stream'));
    expect(application.searchableText, contains('caption;overlay'));
  });

  test('uses the current locale for desktop-entry keywords', () async {
    final localizedRepository = DesktopAppsRepository(
      paths: RuntimePaths(
        environment: <String, String>{
          'HOME': p.join(temporaryDirectory.path, 'home'),
          'XDG_DATA_HOME': dataDirectory.path,
          'XDG_DATA_DIRS': '',
          'LANG': 'zh_CN.UTF-8',
        },
      ),
    );
    _writeFile(
      dataDirectory,
      'applications/localized.desktop',
      '[Desktop Entry]\n'
          'Type=Application\n'
          'Name=Localized App\n'
          'Exec=/usr/bin/localized-app\n'
          'Keywords=default;\n'
          'Keywords[zh]=language;\n'
          'Keywords[zh_CN]=territory;\n',
    );

    final applications = await localizedRepository.loadApplications();
    final application = applications.singleWhere(
      (app) => app.id == 'localized.desktop',
    );

    expect(application.keywords, const <String>['territory']);
    expect(application.searchableText, contains('territory'));
    expect(application.searchableText, isNot(contains('default')));
  });

  test('invalid UTF-8 in one desktop entry does not abort discovery', () async {
    _writeFile(
      dataDirectory,
      'applications/broken.desktop',
      '',
    ).writeAsBytesSync([0xff, 0xfe]);
    _writeFile(
      dataDirectory,
      'applications/valid.desktop',
      '[Desktop Entry]\nName=Valid App\nExec=/usr/bin/valid\n',
    );

    final apps = await repository.loadApplications();
    expect(apps.map((app) => app.id), contains('valid.desktop'));
    expect(apps.map((app) => app.id), isNot(contains('broken.desktop')));
  });

  test(
    'loads linked entries and ignores broken links and directories',
    () async {
      final target = _writeFile(
        temporaryDirectory,
        'exports/target.desktop',
        '[Desktop Entry]\nName=Linked App\nExec=/usr/bin/linked\n',
      );
      final applications = Directory(p.join(dataDirectory.path, 'applications'))
        ..createSync();
      Link(p.join(applications.path, 'linked.desktop')).createSync(target.path);
      Link(p.join(applications.path, 'broken.desktop'))
          .createSync(p.join(temporaryDirectory.path, 'missing.desktop'));
      Directory(p.join(applications.path, 'directory.desktop')).createSync();

      final apps = await repository.loadApplications();
      expect(apps.map((app) => app.id), contains('linked.desktop'));
      expect(apps.map((app) => app.id), isNot(contains('broken.desktop')));
      expect(apps.map((app) => app.id), isNot(contains('directory.desktop')));
    },
  );
}

File _writeFile(Directory root, String relativePath, String contents) {
  final file = File(p.join(root.path, relativePath));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return file;
}
