@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/mappers/gql_public_user_maps.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/mapper/user_availability_mapper.dart';
import 'package:tentura_server/data/repository/user_availability_repository.dart';
import 'package:tentura_server/env.dart';

import '../../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('Hasura metadata — user_availability read permission contract', () {
    late Map<String, dynamic> availabilityTable;
    late Map<String, dynamic> userTable;

    setUpAll(() {
      final metadataFile = File(
        '${Directory.current.path}/../../hasura/metadata.json',
      );
      final metadata =
          jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
      final tables =
          (metadata['metadata'] as Map<String, dynamic>)['sources'][0]['tables']
              as List<dynamic>;
      availabilityTable = tables.cast<Map<String, dynamic>>().firstWhere(
        (entry) =>
            (entry['table'] as Map<String, dynamic>)['name'] ==
            'user_availability',
      );
      userTable = tables.cast<Map<String, dynamic>>().firstWhere(
        (entry) => (entry['table'] as Map<String, dynamic>)['name'] == 'user',
      );
    });

    test('select permission exposes only user_id, is_limited, resume_on', () {
      final permission =
          (availabilityTable['select_permissions'] as List<dynamic>).single
              as Map<String, dynamic>;
      final columns =
          ((permission['permission'] as Map<String, dynamic>)['columns']
                  as List<dynamic>)
              .cast<String>();
      expect(columns, ['is_limited', 'resume_on', 'user_id']);
      expect(columns, isNot(contains('updated_at')));
    });

    test('select permission requires hidden_for_viewer computed field only', () {
      final computedFields =
          (availabilityTable['computed_fields'] as List<dynamic>)
              .map((entry) => (entry as Map<String, dynamic>)['name'] as String)
              .toList();
      expect(computedFields, ['hidden_for_viewer']);

      final permission =
          (availabilityTable['select_permissions'] as List<dynamic>).single
              as Map<String, dynamic>;
      final selectedComputed =
          ((permission['permission'] as Map<String, dynamic>)['computed_fields']
                  as List<dynamic>)
              .cast<String>();
      expect(selectedComputed, ['hidden_for_viewer']);
    });

    test('select filter matches block + effective availability predicate', () {
      final permission =
          (availabilityTable['select_permissions'] as List<dynamic>).single
              as Map<String, dynamic>;
      final filter =
          (permission['permission'] as Map<String, dynamic>)['filter']
              as Map<String, dynamic>;
      expect(filter['_and'], hasLength(2));
      final hiddenFilter = (filter['_and'] as List<dynamic>)[0]
          as Map<String, dynamic>;
      expect(hiddenFilter['hidden_for_viewer'], {'_eq': false});

      final effectiveFilter = (filter['_and'] as List<dynamic>)[1]
          as Map<String, dynamic>;
      expect(effectiveFilter['_or'], hasLength(2));
      final orFilters = (effectiveFilter['_or'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(orFilters[0]['is_limited'], {'_eq': true});
      expect(orFilters[1]['resume_on'], {'_gt': 'now()'});
    });

    test('user_availability has no mutation permissions', () {
      expect(availabilityTable.containsKey('insert_permissions'), isFalse);
      expect(availabilityTable.containsKey('update_permissions'), isFalse);
      expect(availabilityTable.containsKey('delete_permissions'), isFalse);
    });

    test(
      'committed user select metadata still declares limit 10 (static only)',
      () {
        final permission =
            (userTable['select_permissions'] as List<dynamic>).single
                as Map<String, dynamic>;
        final limit =
            (permission['permission'] as Map<String, dynamic>)['limit'];
        expect(limit, 10);
      },
    );
  });

  group('availability read predicate — disposable Postgres', () {
    late Connection writer;
    late TenturaDb db;
    late UserAvailabilityRepository repo;

    const viewerId = 'Uavailrdview01';
    const blockedTargetId = 'Uavailrdblock1';
    const pausePastTargetId = 'Uavailrdppast1';
    const pauseFutureTargetId = 'Uavailrdpfut1';
    const limitedPastTargetId = 'Uavailrdlpast1';

    late String sessionJson;
    late DateTime todayUtc;
    late String yesterdayStr;
    late String tomorrowStr;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      db = TenturaDb(target.databaseEnv);
      repo = UserAvailabilityRepository(db);
      sessionJson = _sessionJson(viewerId);
    });

    setUp(() async {
      if (skipReason != false) {
        return;
      }

      for (final statement in [
        '''DELETE FROM public.user_block '''
            '''WHERE blocker_id = '$viewerId' OR blocked_id = '$viewerId' ''',
        '''DELETE FROM public.user_availability '''
            '''WHERE user_id LIKE 'Uavailrd%' ''',
        '''DELETE FROM public."user" WHERE id LIKE 'Uavailrd%' ''',
      ]) {
        await writer.execute(statement);
      }

      final utcToday = await writer.execute(r'''
SELECT (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date AS today_utc
''');
      todayUtc = utcToday.single.single as DateTime;
      final yesterday = todayUtc.subtract(const Duration(days: 1));
      final tomorrow = todayUtc.add(const Duration(days: 1));
      yesterdayStr = _isoDate(yesterday);
      tomorrowStr = _isoDate(tomorrow);

      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  (@viewerId, 'Viewer', @viewerKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  (@blockedTargetId, 'Blocked target', @blockedKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  (@pausePastTargetId, 'Pause past', @pausePastKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  (@pauseFutureTargetId, 'Pause future', @pauseFutureKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  (@limitedPastTargetId, 'Limited past', @limitedPastKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'viewerId': viewerId,
          'blockedTargetId': blockedTargetId,
          'pausePastTargetId': pausePastTargetId,
          'pauseFutureTargetId': pauseFutureTargetId,
          'limitedPastTargetId': limitedPastTargetId,
          'viewerKey': pgTestPublicKey('availrd', 1),
          'blockedKey': pgTestPublicKey('availrd', 2),
          'pausePastKey': pgTestPublicKey('availrd', 3),
          'pauseFutureKey': pgTestPublicKey('availrd', 4),
          'limitedPastKey': pgTestPublicKey('availrd', 5),
        },
      );

      await writer.execute('''
INSERT INTO public.user_availability (user_id, is_limited, resume_on)
VALUES
  ('$blockedTargetId', true, NULL),
  ('$pausePastTargetId', false, '$yesterdayStr'),
  ('$pauseFutureTargetId', false, '$tomorrowStr'),
  ('$limitedPastTargetId', true, '$yesterdayStr')
ON CONFLICT DO NOTHING
''');

      await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$viewerId', '$blockedTargetId', '$blockedTargetId')
ON CONFLICT DO NOTHING
''');
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await db.close();
      await writer.close();
      await target.drop();
    });

    test('blocked pair is hidden by hidden_for_viewer', () async {
      final hidden = await _queryHiddenAvailabilityUserIds(writer, sessionJson);
      expect(hidden, contains(blockedTargetId));

      final visible = await _queryHasuraVisibleAvailabilityUserIds(
        writer,
        sessionJson,
      );
      expect(visible, isNot(contains(blockedTargetId)));
    });

    test('Hasura read predicate hides expired pause-only rows', () async {
      final visible = await _queryHasuraVisibleAvailabilityUserIds(
        writer,
        sessionJson,
      );
      expect(visible, isNot(contains(pausePastTargetId)));
    });

    test('Hasura read predicate keeps limited rows with past resume_on', () async {
      final visible = await _queryHasuraVisibleAvailabilityUserIds(
        writer,
        sessionJson,
      );
      expect(visible, contains(limitedPastTargetId));
    });

    test('Hasura read predicate keeps future pause rows', () async {
      final visible = await _queryHasuraVisibleAvailabilityUserIds(
        writer,
        sessionJson,
      );
      expect(visible, contains(pauseFutureTargetId));
    });

    test(
      'repository public projection matches Hasura-visible effective state',
      () async {
        final visibleIds = await _queryHasuraVisibleAvailabilityUserIds(
          writer,
          sessionJson,
        );
        final entities = await repo.fetchByUserIds({
          blockedTargetId,
          pausePastTargetId,
          pauseFutureTargetId,
          limitedPastTargetId,
        });

        final gqlByUserId = {
          for (final userId in entities.keys)
            userId: userAvailabilityEntityToGqlMap(
              entity: entities[userId],
              todayUtc: todayUtc,
            ),
        };

        for (final map in gqlByUserId.values) {
          if (map != null) {
            expect(map.keys, isNot(contains('updated_at')));
          }
        }

        expect(gqlByUserId[pausePastTargetId], isNull);
        expect(visibleIds, isNot(contains(pausePastTargetId)));

        expect(gqlByUserId[limitedPastTargetId], {
          'is_limited': true,
          'resume_on': yesterdayStr,
        });
        expect(visibleIds, contains(limitedPastTargetId));

        expect(gqlByUserId[pauseFutureTargetId], {
          'is_limited': false,
          'resume_on': tomorrowStr,
        });
        expect(visibleIds, contains(pauseFutureTargetId));

        final blockedGql = userAvailabilityEntityToGqlMap(
          entity: entities[blockedTargetId],
          todayUtc: todayUtc,
        );
        expect(blockedGql, {'is_limited': true, 'resume_on': null});
        expect(blockedGql!.keys, isNot(contains('updated_at')));
        expect(visibleIds, isNot(contains(blockedTargetId)));
      },
      skip: skipReason,
    );
  });
}

Future<Set<String>> _queryHiddenAvailabilityUserIds(
  Connection writer,
  String sessionJson,
) async {
  final rows = await writer.execute('''
SELECT ua.user_id
FROM public.user_availability ua
WHERE public.user_availability_hidden_for_viewer(ua, '$sessionJson'::json)
ORDER BY ua.user_id
''');
  return rows.map((row) => row[0] as String).toSet();
}

Future<Set<String>> _queryHasuraVisibleAvailabilityUserIds(
  Connection writer,
  String sessionJson,
) async {
  final rows = await writer.execute('''
SELECT ua.user_id
FROM public.user_availability ua
WHERE NOT public.user_availability_hidden_for_viewer(ua, '$sessionJson'::json)
  AND (ua.is_limited OR ua.resume_on > now())
ORDER BY ua.user_id
''');
  return rows.map((row) => row[0] as String).toSet();
}

String _sessionJson(String viewerId) =>
    '{"x-hasura-user-id": "$viewerId"}';

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_AVAILABILITY_READ_PARITY_TEST_DB'] ??
        'tentura_test_availrd_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_AVAILABILITY_READ_PARITY_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
