import 'package:migrant/testing.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

/// Guards the property the squashed baseline relies on: migrant picks the next
/// migration by string comparison against `MAX(schema_version.version)`, so a
/// registry whose versions do not increase in list order would silently skip
/// one. The `0161a`-style out-of-band inserts that made this sharp are gone,
/// but the next migration added after the baseline can reintroduce it.
void main() {
  final migrations = migrationsForTesting;

  test('the registry starts at the squashed baseline', () {
    expect(migrations.first.version, '0193');
  });

  test('migrant visits every registered migration in list order', () async {
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
}
