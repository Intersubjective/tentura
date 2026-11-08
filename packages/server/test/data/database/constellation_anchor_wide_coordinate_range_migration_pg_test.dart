@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_root/domain/constellation/constellation_geometry.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// The newest migration present before the Field placement range was widened.
/// Every stored anchor at that version is held to ±10 units.
const _beforeWideningVersion = '0297';

/// The next unused migration version after [_beforeWideningVersion]: the one
/// that widens the range.
const _wideningVersion = '0298';

/// Axis values probed on both schemas: inside, on and just past the old ±10
/// and the shared bound.
const _probes = [
  0.0,
  10.0,
  -10.0,
  10.001,
  11.0,
  -11.0,
  _bound - 0.001,
  _bound,
  -_bound,
  _bound + 0.001,
  -(_bound + 0.001),
  _bound + 1,
];

const _viewer = 'Ucawiderange01';
const _people = [
  'Ucawidepers001',
  'Ucawidepers002',
  'Ucawidepers003',
  'Ucawidepers004',
  'Ucawidepers005',
];

/// Placements stored under the old ±10 limit.
const _legacyRows = [
  ('CAwideold01', 'Ucawidepers001', 10.0, -10.0),
  ('CAwideold02', 'Ucawidepers002', 0.0, 0.0),
  ('CAwideold03', 'Ucawidepers003', -3.5, 7.25),
];

/// The widened bound: one shared constant for the client, the server
/// validation and the database CHECK.
const _bound = kConstellationCoordinateMaxUnits;

Future<void> main() async {
  test(
    'the widening migration is registered directly after the previous '
    'newest migration',
    () {
      final versions = migrationsForTesting.map((m) => m.version).toList();
      expect(versions, contains(_beforeWideningVersion));
      expect(
        versions,
        contains(_wideningVersion),
        reason:
            'the placement range is widened by a new migration, never by '
            'editing a shipped one',
      );
      expect(
        versions.indexOf(_wideningVersion),
        versions.indexOf(_beforeWideningVersion) + 1,
      );
    },
  );

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_CONSTELLATION_ANCHOR_WIDE_RANGE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_anchor_wide_range',
  );
  final pgSkip = await pgSkipReason(target);

  group('Field placement range widened beyond ±10 units', () {
    late DisposablePgWriterSession session;
    late Connection w;
    late Map<String, List<Object?>> legacyBefore;
    late ServerException? elevenBeforeUpgrade;

    Future<void> upsertAnchor({
      required String id,
      required String personId,
      required String x,
      required String y,
      String version = '1',
    }) => w.execute('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (
  '$id', '$_viewer', '$personId', $x, $y, $version, 1, now()
)
ON CONFLICT (viewer_id, person_id) WHERE person_id IS NOT NULL
DO UPDATE SET x_units = EXCLUDED.x_units, y_units = EXCLUDED.y_units,
  coordinate_space_version = EXCLUDED.coordinate_space_version
''');

    Future<void> clearProbeRow() => w.execute(
      "DELETE FROM public.constellation_anchor WHERE id LIKE 'CAwidenew%'",
    );

    /// Which probe values the schema at [_beforeWideningVersion] stored.
    late Map<double, bool> acceptedBeforeUpgrade;

    /// Whether the current schema stores [value] on both axes; a rejection
    /// must be the coordinate CHECK, never another error.
    Future<bool> schemaAccepts(double value) async {
      for (final (x, y) in [('$value', '0'), ('0', '$value')]) {
        try {
          await upsertAnchor(
            id: 'CAwidenew09',
            personId: _people[4],
            x: x,
            y: y,
          );
        } on ServerException catch (e) {
          expect(e.code, '23514', reason: '($x, $y): ${e.message}');
          expect(e.constraintName, 'constellation_anchor__coord_chk');
          return false;
        } finally {
          await clearProbeRow();
        }
      }
      return true;
    }

    Future<Map<String, List<Object?>>> legacyRows() async {
      final rows = await w.execute('''
SELECT id, person_id, x_units, y_units, coordinate_space_version
FROM public.constellation_anchor
WHERE id LIKE 'CAwideold%'
ORDER BY id
''');
      return {
        for (final row in rows) row[0]! as String: row.sublist(1).toList(),
      };
    }

    Future<void> expectCoordinateCheckViolation(
      Future<Object?> insert, {
      required String reason,
    }) => expectLater(
      insert,
      throwsA(
        isA<ServerException>()
            .having((e) => e.code, 'SQLSTATE', '23514')
            .having(
              (e) => e.constraintName ?? e.message,
              'constraint',
              contains('constellation_anchor__coord_chk'),
            ),
      ),
      reason: reason,
    );

    setUpAll(() async {
      if (pgSkip != null) return;
      session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: _beforeWideningVersion,
      );
      w = session.writer;
      for (final id in [_viewer, ..._people]) {
        await w.execute(
          Sql.named(
            'INSERT INTO public."user" (id, display_name, public_key, '
            'created_at, updated_at) VALUES (@id, @id, @pk, '
            "'2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
          ),
          parameters: {'id': id, 'pk': 'pk-$id'},
        );
      }
      await w.execute(
        'INSERT INTO public.constellation_anchor_cursor (viewer_id) '
        "VALUES ('$_viewer') ON CONFLICT DO NOTHING",
      );
      for (final (id, person, x, y) in _legacyRows) {
        await upsertAnchor(id: id, personId: person, x: '$x', y: '$y');
      }
      legacyBefore = await legacyRows();

      // The old ±10 CHECK is what the upgrade has to widen.
      try {
        await upsertAnchor(
          id: 'CAwidenew01',
          personId: _people[3],
          x: '11',
          y: '-11',
        );
        elevenBeforeUpgrade = null;
      } on ServerException catch (e) {
        elevenBeforeUpgrade = e;
      }

      acceptedBeforeUpgrade = {
        for (final value in _probes) value: await schemaAccepts(value),
      };

      await migrateDbSchema(w);
    });

    tearDownAll(() async {
      if (pgSkip != null) return;
      await tearDownDisposablePgWriter(session: session);
    });

    tearDown(() async {
      if (pgSkip != null) return;
      await clearProbeRow();
    });

    test(
      'an anchor at (11, -11) is rejected before the upgrade and stored '
      'after it',
      () async {
        expect(
          elevenBeforeUpgrade?.code,
          '23514',
          reason: 'at $_beforeWideningVersion the CHECK still caps at ±10',
        );

        await upsertAnchor(
          id: 'CAwidenew01',
          personId: _people[3],
          x: '11',
          y: '-11',
        );
        final row = await w.execute(
          'SELECT x_units, y_units FROM public.constellation_anchor '
          "WHERE id = 'CAwidenew01'",
        );
        expect(row.single[0], 11.0);
        expect(row.single[1], -11.0);
      },
      skip: pgSkip,
    );

    test(
      'the database CHECK bound is the shared constant: ±B is stored, '
      'anything past it is rejected',
      () async {
        expect(_bound, greaterThan(10));
        await upsertAnchor(
          id: 'CAwidenew02',
          personId: _people[3],
          x: '$_bound',
          y: '${-_bound}',
        );
        final row = await w.execute(
          'SELECT x_units, y_units FROM public.constellation_anchor '
          "WHERE id = 'CAwidenew02'",
        );
        expect(row.single[0], _bound);
        expect(row.single[1], -_bound);

        const past = _bound + 0.001;
        for (final (x, y) in [('$past', '0'), ('0', '${-past}')]) {
          await expectCoordinateCheckViolation(
            upsertAnchor(
              id: 'CAwidenew03',
              personId: _people[4],
              x: x,
              y: y,
            ),
            reason: '($x, $y) lies past the bound $_bound',
          );
        }
      },
      skip: pgSkip,
    );

    test(
      'the widened CHECK still rejects NaN, both infinities and a '
      'coordinate space other than 1',
      () async {
        for (final bad in const ["'NaN'", "'Infinity'", "'-Infinity'"]) {
          for (final (x, y) in [('$bad::float8', '0'), ('0', '$bad::float8')]) {
            await expectCoordinateCheckViolation(
              upsertAnchor(
                id: 'CAwidenew04',
                personId: _people[4],
                x: x,
                y: y,
              ),
              reason: 'non-finite ($x, $y)',
            );
          }
        }
        await expectCoordinateCheckViolation(
          upsertAnchor(
            id: 'CAwidenew04',
            personId: _people[4],
            x: '1',
            y: '1',
            version: '2',
          ),
          reason: 'coordinate_space_version 2',
        );
      },
      skip: pgSkip,
    );

    test(
      'anchors stored under the old ±10 limit survive the upgrade unchanged',
      () async {
        expect(legacyBefore, hasLength(_legacyRows.length));
        expect(await legacyRows(), legacyBefore);
      },
      skip: pgSkip,
    );

    test(
      'the shipped schema up to the previous migration still holds the old '
      '±10 CHECK',
      () {
        // Shipped migrations (m0193 included) are not edited to widen the
        // range: only the new migration does.
        expect(acceptedBeforeUpgrade[10.0], isTrue);
        expect(acceptedBeforeUpgrade[-10.0], isTrue);
        expect(acceptedBeforeUpgrade[10.001], isFalse);
        expect(acceptedBeforeUpgrade[11.0], isFalse);
        expect(acceptedBeforeUpgrade[-11.0], isFalse);
      },
      skip: pgSkip,
    );

    test(
      'after the upgrade the database CHECK accepts exactly what the shared '
      'isFiniteV1Axis accepts',
      () async {
        for (final value in _probes) {
          expect(
            await schemaAccepts(value),
            ConstellationAnchorPosition.isFiniteV1Axis(value),
            reason: 'database CHECK and isFiniteV1Axis disagree on $value',
          );
        }
      },
      skip: pgSkip,
    );

    test(
      'the upgrade leaves a single coordinate CHECK, the replaced '
      'constellation_anchor__coord_chk',
      () async {
        final checks = await w.execute("""
SELECT conname
FROM pg_constraint
WHERE conrelid = 'public.constellation_anchor'::regclass
  AND contype = 'c'
  AND pg_get_constraintdef(oid) LIKE '%x_units%'
""");
        expect(
          checks.map((row) => row.single).toList(),
          ['constellation_anchor__coord_chk'],
        );
      },
      skip: pgSkip,
    );
  });
}
