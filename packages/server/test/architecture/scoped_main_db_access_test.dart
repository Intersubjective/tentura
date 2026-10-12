import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Independent main database scopes', () {
    final database = File('lib/data/database/tentura_db.dart');

    test('the main database is not registered as a singleton', () {
      expect(
        RegExp(
          r'^\s*@(?:singleton|Singleton)\b',
          multiLine: true,
        ).hasMatch(database.readAsStringSync()),
        isFalse,
        reason:
            'Independent V2 requests must receive scoped DB handles. '
            'The named auth database may still own its separate pool.',
      );
    });

    test('transaction ownership uses the leased scope executor', () {
      expect(
        RegExp(
          r'@override\s+Future<[^>]+>\s+transaction<[^>]+>\s*\(',
        ).hasMatch(database.readAsStringSync()),
        isFalse,
        reason:
            'TenturaDb must inherit Drift transaction ownership instead '
            'of leasing a connection before acquiring a shared Drift lock.',
      );
    });

    test('pool pinning shims are absent from production database code', () {
      expect(
        _classDefinitions({'_PinnedPoolSession'}),
        isEmpty,
        reason:
            'A connection lease belongs to one scope through commit or '
            'rollback; overlapping requests must not share a pinned session.',
      );
    });

    test('transaction executor spike and its rollout flag are retired', () {
      expect(
        _classDefinitions({
          '_TransactionPinnedPgDatabase',
          '_TransactionPinnedDelegate',
          '_PinnedTransactionDelegate',
        }),
        isEmpty,
        reason:
            'Scoped Drift executors replace the experimental transaction '
            'delegate and its savepoint ownership.',
      );
      expect(
        File('lib/env.dart').readAsStringSync(),
        isNot(contains('DRIFT_TRANSACTION_PINNED_POOL_ENABLED')),
        reason: 'Main DB concurrency must no longer depend on the spike flag.',
      );
    });

    test('constellation work has no separate waiting queue', () {
      final scheduler = File(
        'lib/data/service/constellation_db_scheduler.dart',
      );
      if (!scheduler.existsSync()) return;

      expect(
        RegExp(r'\bQueue\s*<').hasMatch(scheduler.readAsStringSync()),
        isFalse,
        reason:
            'A compatibility adapter may remain, but all main DB scopes '
            'must wait in one bounded admission queue.',
      );
    });
  });
}

List<String> _classDefinitions(Set<String> names) {
  final declaration = RegExp(
    r'^\s*(?:(?:abstract|base|final|sealed)\s+)*class\s+'
    '(${names.map(RegExp.escape).join('|')})\\b',
    multiLine: true,
  );
  return [
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart') && !_isGenerated(file.path))
        for (final match in declaration.allMatches(file.readAsStringSync()))
          '${file.path}: ${match.group(1)}',
  ];
}

bool _isGenerated(String path) => [
  '.g.dart',
  '.freezed.dart',
  '.gr.dart',
  '.config.dart',
  '.schema.dart',
].any(path.endsWith);
