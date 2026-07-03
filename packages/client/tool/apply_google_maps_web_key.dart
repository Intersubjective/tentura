import 'dart:convert';
import 'dart:io';

const _keyName = 'GOOGLE_MAPS_API_KEY';

void main(List<String> args) {
  final sourceMode = args.contains('--source');
  final targetDir = Directory(sourceMode ? 'web' : 'build/web');
  if (!targetDir.existsSync()) {
    stderr.writeln('Google Maps web target not found: ${targetDir.path}');
    exitCode = 1;
    return;
  }

  final apiKey = _googleMapsApiKey();
  File('${targetDir.path}/google_maps_config.js').writeAsStringSync(
    'window.tenturaGoogleMapsApiKey = ${jsonEncode(apiKey)};\n',
  );

  if (apiKey.isEmpty) {
    stderr.writeln(
      '$_keyName is empty; Google Maps web tiles will not load until it is set.',
    );
  }
}

String _googleMapsApiKey() {
  final envValue = Platform.environment[_keyName];
  if (envValue != null && envValue.isNotEmpty) return envValue;

  for (final file in _candidateEnvFiles()) {
    final key = _readKeyFromEnvFile(file);
    if (key != null && key.isNotEmpty) return key;
  }

  return '';
}

Iterable<File> _candidateEnvFiles() sync* {
  yield File('.env');
  yield File('env/local-web.env');
  yield File('../../.env');
}

String? _readKeyFromEnvFile(File file) {
  if (!file.existsSync()) return null;

  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final separatorIndex = line.indexOf('=');
    if (separatorIndex <= 0) continue;

    final key = line.substring(0, separatorIndex).trim();
    if (key != _keyName) continue;

    return line.substring(separatorIndex + 1).trim();
  }

  return null;
}
