import 'dart:async';
import 'dart:io';

/// Watches completed PNGs from deniald's asynchronous screenshot writer.
///
/// A queued screenshot command is not proof of a successful save. The PNG's
/// trailing IEND chunk is only present once its encoder has finished.
class ScreenshotFileMonitor {
  ScreenshotFileMonitor({required this.directory, required this.onSaved});

  final Directory directory;
  final void Function(String path) onSaved;

  StreamSubscription<FileSystemEvent>? _subscription;
  final Map<String, Timer> _pending = <String, Timer>{};
  final Set<String> _reported = <String>{};
  bool _disposed = false;

  Future<void> start() async {
    try {
      await directory.create(recursive: true);
      if (_disposed) return;
      _subscription = directory
          .watch(events: FileSystemEvent.create | FileSystemEvent.modify)
          .listen(
            _onFileEvent,
            onError: (Object error) {
              stderr.writeln('Denial screenshot feedback watcher: $error');
            },
          );
    } on FileSystemException catch (error) {
      stderr.writeln('Could not watch screenshots for feedback: $error');
    }
  }

  void _onFileEvent(FileSystemEvent event) {
    if (_disposed || event.isDirectory) return;
    final path = event.path;
    final name = path.split(Platform.pathSeparator).last;
    if (!RegExp(r'^Screenshot-\d+-\d{3}(?:-\d+)?\.png$').hasMatch(name) ||
        _reported.contains(path)) {
      return;
    }
    _scheduleCheck(path, 0);
  }

  void _scheduleCheck(String path, int attempt) {
    _pending.remove(path)?.cancel();
    _pending[path] = Timer(const Duration(milliseconds: 110), () async {
      _pending.remove(path);
      if (_disposed || _reported.contains(path)) return;
      if (await isFinishedPng(File(path))) {
        if (_disposed || _reported.contains(path)) return;
        _reported.add(path);
        // The watcher runs for the lifetime of the shell; bound its memory.
        if (_reported.length > 64) _reported.remove(_reported.first);
        onSaved(path);
      } else if (attempt < 80) {
        _scheduleCheck(path, attempt + 1);
      }
    });
  }

  /// Reject unfinished or truncated files without decoding a full-size PNG.
  static Future<bool> isFinishedPng(File file) async {
    RandomAccessFile? input;
    try {
      input = await file.open();
      final length = await input.length();
      if (length < 20) return false;
      await input.setPosition(length - 12);
      final trailer = await input.read(8);
      return trailer.length == 8 &&
          trailer[0] == 0 &&
          trailer[1] == 0 &&
          trailer[2] == 0 &&
          trailer[3] == 0 &&
          trailer[4] == 73 &&
          trailer[5] == 69 &&
          trailer[6] == 78 &&
          trailer[7] == 68; // zero-sized PNG IEND chunk
    } on FileSystemException {
      return false;
    } finally {
      await input?.close();
    }
  }

  void dispose() {
    _disposed = true;
    for (final timer in _pending.values) {
      timer.cancel();
    }
    _pending.clear();
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
  }
}

Future<Directory> denialScreenshotDirectory() async {
  final override = Platform.environment['DENIAL_SCREENSHOT_DIR'];
  if (override != null && override.isNotEmpty) return Directory(override);
  final home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty) return Directory.systemTemp;
  try {
    final result = await Process.run('xdg-user-dir', const <String>[
      'PICTURES',
    ]);
    if (result.exitCode == 0) {
      final pictures = result.stdout.toString().trim();
      if (pictures.isNotEmpty) {
        return Directory('$pictures/Screenshots');
      }
    }
  } on ProcessException {
    // xdg-user-dir may not be installed in minimal shells.
  }
  return Directory('$home/Pictures/Screenshots');
}
