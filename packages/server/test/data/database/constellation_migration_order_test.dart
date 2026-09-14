import 'package:migrant/migrant.dart';
import 'package:migrant/testing.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

void main() {
  final migrations = migrationsForTesting;

  test('migrant visits every registered migration from every prefix', () async {
    final source = InMemory(migrations);
    expect(await source.getInitial(), same(migrations.first));
    for (var index = 0; index < migrations.length; index++) {
      final current = migrations[index];
      final next = await source.getNext(current.version);
      if (index == migrations.length - 1) {
        expect(next, isNull);
      } else {
        expect(
          migrations[index + 1].version.compareTo(current.version),
          greaterThan(0),
          reason: 'Versions must increase after ${current.version}',
        );
        expect(
          next,
          same(migrations[index + 1]),
          reason: 'migrant must not skip a migration after ${current.version}',
        );
      }
    }
  });

  test(
    'fresh installs create the cache before the read-wall function',
    () async {
      final pending = await _pending(migrations, '0161');
      expect(
        pending.take(4).map((migration) => migration.version),
        ['0161a', '0162', '0163', '0163a'],
      );
      expect(m0161a.statements, m0163a.statements);
      expect(
        m0161a.statements.join('\n'),
        contains(
          'CREATE OR REPLACE TRIGGER vote_user_bump_direct_trust_version',
        ),
      );
    },
  );

  test(
    '0169 restores both skipped function bodies without behavior changes',
    () {
      expect(m0169.version.compareTo('0168'), greaterThan(0));
      expect(m0169.statements, [...m0162.statements, ...m0163.statements]);
      expect(
        m0169.statements.join('\n'),
        contains(
          'CREATE OR REPLACE FUNCTION public.constellation_trust_edges(',
        ),
      );
      expect(
        m0169.statements.join('\n'),
        contains('CREATE OR REPLACE FUNCTION public.beacon_can_read_content('),
      );
    },
  );

  for (final current in ['0161', '0162', '0163a', '0168']) {
    test('upgrade from $current reaches the forward repair', () async {
      final pending = await _pending(migrations, current);
      expect(pending, contains(same(m0169)));
      if (current == '0162') {
        expect(pending.take(2), [m0163, m0163a]);
      }
      if (current == '0163a' || current == '0168') {
        expect(pending, isNot(contains(m0162)));
        expect(pending, isNot(contains(m0163)));
        expect(
          pending.expand((migration) => migration.statements),
          containsAll([...m0162.statements, ...m0163.statements]),
        );
      }
    });
  }
}

Future<List<Migration>> _pending(
  List<Migration> migrations,
  String current,
) async {
  final source = InMemory(migrations);
  final pending = <Migration>[];
  while (true) {
    final next = await source.getNext(current);
    if (next == null) return pending;
    expect(next.version.compareTo(current), greaterThan(0));
    pending.add(next);
    current = next.version;
  }
}
