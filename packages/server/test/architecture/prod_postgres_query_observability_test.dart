// Prod postgres must preload pg_stat_statements + auto_explain with the
// owner-approved thresholds, and the deploy guide must carry the runbook for
// reading them.

@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:test/test.dart';

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

String _read(String relPath) =>
    File('${_repoRoot().path}/$relPath').readAsStringSync();

/// The body of the `postgres:` service in compose.prod.yaml, read from disk so
/// the test needs no docker CLI (the server CI image has none).
String _postgresServiceBlock() {
  final lines = _read('compose.prod.yaml').split('\n');
  final start = lines.indexWhere(
    (l) => RegExp(r'^  postgres:\s*$').hasMatch(l),
  );
  expect(start, greaterThanOrEqualTo(0), reason: 'no postgres service');
  var end = start + 1;
  // The service ends at the next two-space (service) or column-0 key.
  while (end < lines.length && !RegExp(r'^(  \S|\S)').hasMatch(lines[end])) {
    end++;
  }
  return lines.sublist(start + 1, end).join('\n');
}

/// The postgres service command split into the executable and its
/// `-c name=value` server settings.
({String executable, Map<String, String> settings}) _postgresCommand() {
  final block = _postgresServiceBlock();
  final commandAt = RegExp('^    command:', multiLine: true).firstMatch(block);
  expect(commandAt, isNotNull, reason: 'postgres service has no command');
  // The command runs until the next service-level key (four-space indent).
  final rest = block.substring(commandAt!.end);
  final next = RegExp('^    [A-Za-z_]', multiLine: true).firstMatch(rest);
  final raw = next == null ? rest : rest.substring(0, next.start);
  final args = raw
      .replaceAll(RegExp(r'^\s*-\s+', multiLine: true), ' ')
      .replaceAll(RegExp('[\'"]'), '')
      .split(RegExp(r'\s+'))
      .where((a) => a.isNotEmpty)
      .toList();
  expect(args, isNotEmpty, reason: 'postgres command is empty');
  final settings = <String, String>{};
  for (var i = 1; i < args.length; i++) {
    if (args[i] != '-c') continue;
    expect(i + 1, lessThan(args.length), reason: 'dangling -c');
    final setting = args[++i];
    final eq = setting.indexOf('=');
    expect(eq, greaterThan(0), reason: '-c $setting is not name=value');
    settings[setting.substring(0, eq)] = setting.substring(eq + 1);
  }
  return (executable: args.first, settings: settings);
}

/// Lines of the runbook section whose `##`/`###` heading mentions
/// pg_stat_statements, up to the next heading of the same or higher level
/// (`#` comment lines inside code fences are not headings).
List<String> _runbookSection(String guide) {
  final lines = guide.split('\n');
  var inFence = false;
  int? level;
  int? start;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final heading = RegExp('^(#{1,6}) (.*)').firstMatch(lines[i]);
    if (heading == null) continue;
    final depth = heading.group(1)!.length;
    if (start == null) {
      if (depth >= 2 &&
          depth <= 3 &&
          heading.group(2)!.contains('pg_stat_statements')) {
        start = i;
        level = depth;
      }
    } else if (depth <= level!) {
      return lines.sublist(start, i);
    }
  }
  return start == null ? const [] : lines.sublist(start);
}

void main() {
  group('prod postgres command in compose.prod.yaml', () {
    late String executable;
    late Map<String, String> settings;
    setUpAll(() {
      final command = _postgresCommand();
      executable = command.executable;
      settings = command.settings;
    });

    test('starts the postgres server binary', () {
      expect(executable, 'postgres');
    });

    test('preloads pg_stat_statements and auto_explain', () {
      expect(
        settings['shared_preload_libraries'],
        'pg_stat_statements,auto_explain',
      );
    });

    test('tracks all statements with I/O timing', () {
      expect(settings['pg_stat_statements.track'], 'all');
      expect(settings['track_io_timing'], 'on');
    });

    test('logs statements slower than one second', () {
      expect(settings['log_min_duration_statement'], '1000');
    });

    test('auto_explain logs plans slower than two seconds with analyze '
        'and buffers', () {
      expect(settings['auto_explain.log_min_duration'], '2000');
      expect(settings['auto_explain.log_analyze'], 'on');
      expect(settings['auto_explain.log_buffers'], 'on');
    });
  });

  group('production deploy guide query-observability runbook', () {
    late List<String> section;
    setUpAll(
      () => section = _runbookSection(_read('docs/production-deploy.md')),
    );

    test('has a pg_stat_statements section', () {
      expect(
        section,
        isNotEmpty,
        reason: 'no ##/### heading mentioning pg_stat_statements',
      );
    });

    test('shows the top-queries SQL ordered by total, max time and calls', () {
      final text = section.join('\n');
      expect(
        RegExp(
          r'FROM\s+pg_stat_statements\b',
          caseSensitive: false,
        ).hasMatch(text),
        isTrue,
        reason: 'no query selecting FROM pg_stat_statements',
      );
      for (final column in ['total_exec_time', 'max_exec_time', 'calls']) {
        expect(
          RegExp(
            'ORDER\\s+BY\\s+(\\w+\\.)?$column\\s+DESC',
            caseSensitive: false,
          ).hasMatch(text),
          isTrue,
          reason: 'no query ordered by $column',
        );
      }
    });

    test('explains resetting the counters', () {
      expect(section.join('\n'), contains('pg_stat_statements_reset()'));
    });

    test('says auto_explain plans land in the postgres journald log', () {
      final autoExplainLines = [
        for (var i = 0; i < section.length; i++)
          if (section[i].contains('auto_explain')) i,
      ];
      expect(
        autoExplainLines,
        isNotEmpty,
        reason: 'auto_explain not described in the section',
      );
      // Prose and the journalctl example may sit on neighbouring lines, so
      // look for both within a small window around an auto_explain mention.
      final tiedToPostgresJournal = autoExplainLines.any((i) {
        final from = i - 6 < 0 ? 0 : i - 6;
        final to = i + 7 > section.length ? section.length : i + 7;
        final window = section.sublist(from, to).join('\n');
        return RegExp(
              'journald|journalctl',
              caseSensitive: false,
            ).hasMatch(window) &&
            RegExp(r'postgres\b', caseSensitive: false).hasMatch(window);
      });
      expect(
        tiedToPostgresJournal,
        isTrue,
        reason: 'auto_explain is not tied to the postgres journald log',
      );
    });
  });
}
