import 'dart:io';

/// Opens [path] in the platform file manager: Explorer on Windows, Finder on
/// macOS. Throws if the file manager could not be launched.
Future<void> openFolder(String path) async {
  if (Platform.isWindows) {
    // explorer.exe exits non-zero even when it opened the window, so its
    // exit code says nothing about success.
    await Process.run('explorer', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else {
    await Process.run('xdg-open', [path]);
  }
}
