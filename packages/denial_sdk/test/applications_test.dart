import 'package:denial_sdk/applications.dart';
import 'package:test/test.dart';

void main() {
  test('application metadata retains the shell search vocabulary', () {
    const app = DesktopApp(
      id: 'org.example.Editor.desktop',
      name: 'Editor',
      exec: 'editor --open %F',
      desktopPath: '/usr/share/applications/org.example.Editor.desktop',
      categories: ['Development', 'TextEditor'],
      keywords: ['Code', 'Text'],
    );

    expect(
      app.searchableText,
      'org.example.editor.desktop editor development texteditor code text',
    );
    expect(app.searchableText, isNot(contains('--open')));
    expect(app.iconPath, isNull);
    expect(app.startupWmClass, isNull);
  });
}
