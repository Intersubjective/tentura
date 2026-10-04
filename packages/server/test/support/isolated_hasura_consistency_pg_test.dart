@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'disposable_pg_target.dart';
import 'hasura_pg_jwt_keys.dart';
import 'isolated_hasura_session.dart';

/// `assertMetadataConsistent()` must pass for the repo metadata and throw for
/// metadata whose permission references a column that does not exist —
/// `applyRepoMetadata` tolerates inconsistent metadata, so only this assertion
/// notices a silently dropped permission.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_HASURA_CONSISTENCY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_hasura_consistency',
  );
  final postgresSkipReason = await pgSkipReason(target);
  final dockerAvailable =
      postgresSkipReason == null &&
      await IsolatedHasuraSession.isDockerAvailable();
  final skipReason =
      postgresSkipReason ??
      (dockerAvailable ? false : 'Docker not available for isolated Hasura');

  test(
    'pgSkipReason returns null instead of throwing for a reachable Postgres '
    'in REQUIRED mode',
    () async {
      final reason = await pgSkipReason(
        target,
        environment: const {'TENTURA_PG_TESTS_REQUIRED': '1'},
      );

      expect(reason, isNull);
    },
    skip: postgresSkipReason ?? false,
  );

  group('Hasura metadata consistency — disposable Postgres', () {
    late DisposablePgWriterSession pg;
    late IsolatedHasuraSession hasura;

    if (skipReason == false) {
      setUpAll(() async {
        pg = await setUpDisposablePgWriter(target: target);
        hasura = await IsolatedHasuraSession.start(
          databaseEnv: target.databaseEnv,
          jwtPublicPem: loadJwtKeysForHasuraPgTests().publicKey,
        );
      });

      tearDownAll(() async {
        try {
          await hasura.stop();
        } finally {
          await tearDownDisposablePgWriter(session: pg);
        }
      });
    }

    test(
      'passes for the repo metadata',
      () async {
        await hasura.applyRepoMetadata();

        await hasura.assertMetadataConsistent();
      },
      skip: skipReason,
    );

    test(
      'throws a StateError listing every inconsistent object Hasura reports '
      'when a beacon permission references a non-existent column',
      () async {
        await _replaceMetadataWithBrokenBeaconPermission(hasura);
        final reasons = await _inconsistentObjectReasons(hasura);
        expect(reasons, isNotEmpty);

        await expectLater(
          hasura.assertMetadataConsistent(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf([for (final reason in reasons) contains(reason)]),
            ),
          ),
        );
      },
      skip: skipReason,
    );
  });
}

/// Applies a copy of the repo metadata whose role `user` beacon select
/// permission also lists a column that does not exist.
Future<void> _replaceMetadataWithBrokenBeaconPermission(
  IsolatedHasuraSession hasura,
) async {
  final metadataFile = File(
    '${Directory.current.path}/../../hasura/metadata.json',
  );
  final metadata =
      jsonDecode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
  final sources =
      (metadata['metadata'] as Map<String, dynamic>)['sources']
          as List<dynamic>;
  var patched = false;
  for (final source in sources) {
    for (final table in (source as Map<String, dynamic>)['tables'] as List) {
      final tableMap = table as Map<String, dynamic>;
      if ((tableMap['table'] as Map<String, dynamic>)['name'] != 'beacon') {
        continue;
      }
      for (final permission in tableMap['select_permissions'] as List) {
        final permissionMap = permission as Map<String, dynamic>;
        if (permissionMap['role'] != 'user') continue;
        final columns =
            (permissionMap['permission'] as Map<String, dynamic>)['columns']
                  as List<dynamic>
              ..add('no_such_column_for_consistency_test');
        expect(columns, isNotEmpty);
        patched = true;
      }
    }
  }
  expect(patched, isTrue, reason: 'beacon user select permission not found');

  await _postMetadata(hasura, 'replace_metadata', {
    'allow_inconsistent_metadata': true,
    'metadata': metadata['metadata'],
  });
}

/// The `reason` of each object in Hasura's own `get_inconsistent_metadata`.
Future<List<String>> _inconsistentObjectReasons(
  IsolatedHasuraSession hasura,
) async {
  final body = await _postMetadata(
    hasura,
    'get_inconsistent_metadata',
    <String, dynamic>{},
  );
  expect(body['is_consistent'], isFalse);
  return [
    for (final object in body['inconsistent_objects'] as List<dynamic>)
      (object as Map<String, dynamic>)['reason'] as String,
  ];
}

Future<Map<String, dynamic>> _postMetadata(
  IsolatedHasuraSession hasura,
  String type,
  Map<String, dynamic> args,
) async {
  final response = await http.post(
    Uri.parse('${hasura.baseUrl}/v1/metadata'),
    headers: {
      'Content-Type': 'application/json',
      'X-Hasura-Admin-Secret': hasura.adminSecret,
    },
    body: jsonEncode({'type': type, 'args': args}),
  );
  expect(response.statusCode, 200, reason: response.body);
  return jsonDecode(response.body) as Map<String, dynamic>;
}
