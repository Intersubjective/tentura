@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

const _setting = 'tentura.owner_scope_enforce';
const _triggerMigration = 'data/database/migration/m0332.dart';

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/compose.prod.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('repo root not found');
    }
    dir = parent;
  }
  return dir;
}

String? _postgresCommand(String compose) {
  final service = RegExp(
    r'^  postgres:[ \t]*\n(?:^ {4,}[^\n]*\n|^\n)*',
    multiLine: true,
  ).stringMatch(compose);
  expect(
    service,
    isNotNull,
    reason: 'compose.dev.yaml has no postgres service',
  );
  final command = RegExp(
    r'^    command:([^\n]*)(\n(?:^ {6,}[^\n]*\n)*)',
    multiLine: true,
  ).firstMatch(service!);
  return command?.group(0);
}

bool _enablesOwnerScope(String? command) {
  if (command == null) return false;
  final arguments = command
      .replaceFirst('    command:', '')
      .replaceAll(RegExp(r'(?:^|[ \t]+)#.*', multiLine: true), '')
      .replaceAll(RegExp(r'^[ \t]*-[ \t]+', multiLine: true), ' ')
      .replaceAll(RegExp(r'[\[\],>]'), ' ')
      .replaceAll(RegExp('''['"]'''), '')
      .trim();
  final executable = arguments.split(RegExp(r'\s+')).first;
  if (executable != 'postgres' && !executable.startsWith('-')) return false;
  final assignments = RegExp(
    '(?:^|\\s)(?:-c\\s+|--)${RegExp.escape(_setting)}\\s*=\\s*(\\S+)',
  ).allMatches(arguments);
  return assignments.lastOrNull?.group(1) == 'on';
}

List<String> _unexpectedServerReferences(Directory lib) {
  final triggerRead = RegExp(
    "current_setting\\(\\s*'${RegExp.escape(_setting)}'\\s*,\\s*true\\s*\\)",
  );
  final unexpected = <String>[];
  for (final entry in lib.listSync(recursive: true)) {
    if (entry is! File ||
        !entry.path.endsWith('.dart') ||
        RegExp(r'\.(g|freezed|gr|config|schema)\.dart$').hasMatch(entry.path)) {
      continue;
    }
    final relativePath = entry.path.substring(lib.path.length + 1);
    final lines = entry.readAsLinesSync();
    for (final (index, line) in lines.indexed) {
      final source = relativePath == _triggerMigration
          ? line.replaceFirst(triggerRead, '')
          : line;
      if (source.contains('owner_scope_enforce')) {
        unexpected.add('$relativePath:${index + 1}');
      }
    }
  }
  return unexpected..sort();
}

void main() {
  test(
    'development enables owner scope enforcement without opting in production',
    () {
      final root = _repoRoot().path;
      final dev = File('$root/compose.dev.yaml').readAsStringSync();
      final prod = File('$root/compose.prod.yaml').readAsStringSync();

      expect(
        {
          'development postgres enables enforcement': _enablesOwnerScope(
            _postgresCommand(dev),
          ),
          'production compose mentions the setting': prod.contains(_setting),
          'server references other than the trigger read':
              _unexpectedServerReferences(
                Directory('$root/packages/server/lib'),
              ),
        },
        {
          'development postgres enables enforcement': true,
          'production compose mentions the setting': false,
          'server references other than the trigger read': <String>[],
        },
      );
    },
  );
}
