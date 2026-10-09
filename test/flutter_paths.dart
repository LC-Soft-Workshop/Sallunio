import 'dart:io';

String materialIconsPath() {
  final configured = Platform.environment['FLUTTER_ROOT'];
  var directory = configured == null
      ? File(Platform.resolvedExecutable).parent
      : Directory(configured);
  while (true) {
    final file = File(
      '${directory.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (file.existsSync()) return file.path;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Police MaterialIcons introuvable dans le SDK Flutter');
    }
    directory = parent;
  }
}
