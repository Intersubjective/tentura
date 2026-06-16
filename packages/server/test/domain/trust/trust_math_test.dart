import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_math.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  group('mappers', () {
    test('vote amount maps to mild bins', () {
      expect(voteAmountToBin(1), TrustBin.good);
      expect(voteAmountToBin(-1), TrustBin.bad);
      expect(voteAmountToBin(0), TrustBin.noEffect);
    });

    test('NO_BASIS review value is skipped', () {
      expect(reviewValueToBin(0), isNull);
    });
  });

  final postgresReachable = await _canConnectPostgres();
  group('trust_edge_weight (SQL)', () {
    late TenturaDb db;

    setUpAll(() async {
      if (!postgresReachable) return;
      final env = Env(
        environment: Environment.test,
        pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
        pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
        pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
        printEnv: false,
        isDebugModeOn: false,
      );
      db = TenturaDb(env);
      await db.customStatement(r'''
CREATE OR REPLACE FUNCTION public.trust_edge_weight(
  _s_very_bad double precision,
  _s_bad double precision,
  _s_no_effect double precision,
  _s_good double precision,
  _s_very_good double precision,
  _f double precision
) RETURNS double precision
  LANGUAGE sql
  IMMUTABLE
  AS $$
  SELECT (_f * (-5 * _s_very_bad - _s_bad + _s_good + 5 * _s_very_good))
       / (5 + _f * (_s_very_bad + _s_bad + _s_no_effect + _s_good + _s_very_good));
$$;
''');
    });

    tearDownAll(() async {
      if (postgresReachable) await db.close();
    });

    test('prior-only is neutral', () async {
      final row = await db
          .customSelect(
            'SELECT trust_edge_weight(0::float8, 0::float8, 0::float8, 0::float8, 0::float8, 1::float8) AS w',
          )
          .getSingle();
      expect(row.read<double>('w'), closeTo(0, 1e-9));
    }, skip: postgresReachable ? false : 'local Postgres not reachable');

    test('friend vote +3 good with f=1 is ~0.375', () async {
      final row = await db
          .customSelect(
            'SELECT trust_edge_weight(0::float8, 0::float8, 0::float8, 3::float8, 0::float8, 1::float8) AS w',
          )
          .getSingle();
      expect(row.read<double>('w'), closeTo(0.375, 1e-9));
    }, skip: postgresReachable ? false : 'local Postgres not reachable');

    test('one good review +1 is ~0.167', () async {
      final row = await db
          .customSelect(
            'SELECT trust_edge_weight(0::float8, 0::float8, 0::float8, 1::float8, 0::float8, 1::float8) AS w',
          )
          .getSingle();
      expect(row.read<double>('w'), closeTo(1 / 6, 1e-9));
    }, skip: postgresReachable ? false : 'local Postgres not reachable');

    test('one very_bad review is strongly negative', () async {
      final row = await db
          .customSelect(
            'SELECT trust_edge_weight(1::float8, 0::float8, 0::float8, 0::float8, 0::float8, 1::float8) AS w',
          )
          .getSingle();
      expect(row.read<double>('w'), lessThan(-0.5));
    }, skip: postgresReachable ? false : 'local Postgres not reachable');

    test('deflation f=0.5 reduces magnitude toward zero', () async {
      final full = await db
          .customSelect(
            'SELECT trust_edge_weight(0::float8, 0::float8, 0::float8, 3::float8, 0::float8, 1::float8) AS w',
          )
          .getSingle();
      final half = await db
          .customSelect(
            'SELECT trust_edge_weight(0::float8, 0::float8, 0::float8, 3::float8, 0::float8, 0.5::float8) AS w',
          )
          .getSingle();
      final wFull = full.read<double>('w');
      final wHalf = half.read<double>('w');
      expect(wHalf.abs(), lessThan(wFull.abs()));
      expect(wHalf, greaterThan(0));
    }, skip: postgresReachable ? false : 'local Postgres not reachable');
  });
}

Future<bool> _canConnectPostgres() async {
  try {
    final env = Env(
      environment: Environment.test,
      pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
      pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
      pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
      printEnv: false,
      isDebugModeOn: false,
    );
    final db = TenturaDb(env);
    await db.customSelect('SELECT 1').getSingle();
    await db.close();
    return true;
  } catch (_) {
    return false;
  }
}
