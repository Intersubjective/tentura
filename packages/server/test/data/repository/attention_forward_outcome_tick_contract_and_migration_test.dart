@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../support/attention_axis_contract.dart';

/// The forward-row outcome tick is recorded in the attention contract JSON
/// and in a shipped migration. These tests pin what those records must say
/// once «Read all» and opening a Request also clear the tick, and once the
/// trigger records only moves INTO an outcome status.
String _squash(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

File _repoFile(String serverRelative) {
  for (final candidate in [serverRelative, 'packages/server/$serverRelative']) {
    final file = File(candidate);
    if (file.existsSync()) return file;
  }
  throw StateError('$serverRelative not found');
}

void main() {
  group('attention contract forward outcome tick', () {
    late String section;

    setUpAll(() {
      // Everything the contract states about the tick, whichever field
      // carries it (description, markSeen, a dedicated field, SQL fragments).
      section = _squash(
        AttentionAxisContract.load().forwardOutcomeTick.prose,
      );
    });

    test(
      'the contract records that markAllSeen and markSeenForBeacon set the '
      "viewer's outcome_seen_at",
      () {
        expect(section, contains('markallseen'));
        expect(section, contains('markseenforbeacon'));
        expect(section, contains('outcome_seen_at'));
      },
    );

    test(
      'the contract records that a move into status 0 is not recorded while '
      'moves into the outcome statuses are',
      () {
        expect(
          RegExp(
            r'\b(status 0|into 0|to 0|needsme|needs me)\b',
          ).hasMatch(section),
          isTrue,
          reason: 'status 0 (needs me) is named as the non-outcome status',
        );
        expect(
          RegExp(
            r'into an outcome|into outcome|\b1(\W+2\W+3)?\W+4\b',
          ).hasMatch(section),
          isTrue,
          reason: 'the recorded moves are named: into an outcome / 1-4',
        );
      },
    );
  });

  group('outcome trigger migration', () {
    /// m0301 shipped; the fix must not edit it (a shipped migration is
    /// never edited in place).
    test('m0301 is unchanged', () {
      final bytes = _repoFile(
        'lib/data/database/migration/m0301.dart',
      ).readAsBytesSync();
      expect(
        sha256.convert(bytes).toString(),
        'afc87c84f6c46652c876b86d24f7958c2ad0c1da2a2096b8b8fd845cc2bd86aa',
      );
    });

    test(
      'a later migration redefines the outcome trigger and is registered',
      () {
        final dir = _repoFile('lib/data/database/migration/m0301.dart').parent;
        final later = <File>[];
        for (final entity in dir.listSync()) {
          final match = RegExp(
            r'm(\d{4})\.dart$',
          ).firstMatch(entity.uri.pathSegments.last);
          if (entity is File && match != null) {
            if (int.parse(match.group(1)!) > 301) later.add(entity);
          }
        }
        final fixes = [
          for (final file in later)
            if (_squash(file.readAsStringSync()).contains(
              'function public.inbox_item_record_outcome_change',
            ))
              file,
        ];
        expect(
          fixes,
          isNotEmpty,
          reason:
              'a migration numbered above 0301 must CREATE OR REPLACE '
              'inbox_item_record_outcome_change',
        );

        final registry = File(
          '${dir.path}/_migrations.dart',
        ).readAsStringSync();
        for (final file in fixes) {
          final name = file.uri.pathSegments.last.replaceAll('.dart', '');
          expect(registry, contains("part '$name.dart';"), reason: name);
          expect(
            RegExp('^\\s*$name,\$', multiLine: true).hasMatch(registry),
            isTrue,
            reason: '$name is in the migration list',
          );
        }
      },
    );
  });
}
