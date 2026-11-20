@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/env.dart';

import '../support/beacon_metadata_reader.dart';
import '../support/disposable_pg_target.dart';
import '../support/hasura_pg_jwt_keys.dart';
import '../support/isolated_hasura_session.dart';
import '../support/post_bud_privacy_fixture.dart';

const _post = PostBudPrivacyFixture.post;
const _bob = PostBudPrivacyFixture.bob;
const _carol = PostBudPrivacyFixture.carol;
const _helper = PostBudPrivacyFixture.helper;
const _title = PostBudPrivacyFixture.title;

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_BUD_HASURA_PRIVACY_TEST_DB',
    defaultNamePrefix: 'tentura_test_bud_hasura_privacy',
  );
  final environment = Platform.environment;
  final inCi =
      environment['CI'] == 'true' || environment['GITHUB_ACTIONS'] == 'true';
  final skip = await pgSkipReason(
    target,
    environment: {
      ...environment,
      if (inCi) pgTestsRequiredEnvVar: '1',
    },
  );
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }
  final useHasura =
      !inCi &&
      await IsolatedHasuraSession.isDockerAvailable(requiredForPg: false);

  late PostBudPrivacyFixture fixture;
  late final Future<Map<String, Object?>> Function(String, String) query;

  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    final database = openDisposablePgDatabase(target);
    addTearDown(
      () => tearDownDisposablePgWriter(session: session, drift: database),
    );
    if (environment['TENTURA_BUD_PRIVACY_FIXTURE_VIEW'] == '1') {
      // A separately tracked projection lets metadata fixtures vary the
      // destination permission without changing the root beacon permission.
      await session.writer.execute('''
CREATE VIEW public.beacon_privacy_fixture AS
SELECT id, user_id, parent_beacon_id, title FROM public.beacon
''');
      await session.writer.execute(r'''
CREATE FUNCTION public.beacon_privacy_fixture_can_read_content(
  fixture_row public.beacon_privacy_fixture, hasura_session json
) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT public.beacon_get_can_read_content(beacon, hasura_session)
  FROM public.beacon AS beacon WHERE beacon.id = fixture_row.id
$$
''');
    }
    fixture = PostBudPrivacyFixture(
      session.writer,
      database,
      target.databaseEnv,
    );
    if (!useHasura) return;

    final jwt = loadJwtKeysForHasuraPgTests();
    final auth = AuthCase(
      _UnusedUsers(),
      _UnusedInvitations(),
      env: Env(
        environment: Environment.test,
        printEnv: false,
        publicKey: jwt.publicKey,
        privateKey: jwt.privateKey,
      ),
      logger: Logger('PostBudHasuraPrivacy'),
    );
    final hasura = await IsolatedHasuraSession.start(
      databaseEnv: target.databaseEnv,
      jwtPublicPem: jwt.publicKey,
    );
    addTearDown(hasura.stop);
    await hasura.applyRepoMetadata();
    query = (viewer, document) async {
      final response = await http.post(
        Uri.parse('${hasura.baseUrl}/v1/graphql'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${auth.issueAccessToken(viewer).rawToken}',
        },
        body: jsonEncode({'query': document}),
      );
      expect(response.statusCode, 200);
      if (jsonDecode(response.body) case final Map<String, Object?> wire) {
        expect(wire['errors'], isNull, reason: response.body);
        if (wire['data'] case final Map<String, Object?> data) return data;
      }
      throw StateError('Invalid Hasura response: ${response.body}');
    };
  });

  test(
    'Hasura reveals Request lineage only to viewers who can read its source',
    () async {
      final metadata = useHasura
          ? null
          : await BeaconMetadataReader.fromRepo(fixture.writer);
      await fixture.seedPost();
      final childField = RegExp('child|descendant', caseSensitive: false);
      final countField = RegExp('count|total|number|num', caseSensitive: false);
      final selectableFields =
          metadata?.fields ?? await _hasuraBeaconFields(query, childField);
      final childFields = selectableFields.where(childField.hasMatch).toList();
      final childCounts = childFields.where(countField.hasMatch).toList();
      expect(
        childFields.where((field) => !childCounts.contains(field)),
        isEmpty,
        reason:
            'Any exposed child relationship needs an authenticated privacy check',
      );

      void expectChildCounts(Object? post, int expected, String viewer) {
        for (final field in childCounts) {
          expect(
            post,
            containsPair(field, expected),
            reason: '$viewer sees the readable count',
          );
        }
      }

      const accessFields = [
        'can_read_content',
        'can_read_involvement',
        'can_read_admitted_helpers',
        'access_level',
        'access_reasons',
      ];
      const lineageFields = [
        'lineage_parent_beacon_id',
        'lineage_root_beacon_id',
      ];
      final post = (
        ids: [_post],
        fields: [
          'id',
          'title',
          'description',
          'post_root_message_id',
          ...accessFields,
          ...childCounts,
        ],
      );
      Future<Map<String, Object?>> read(
        String viewer,
        Map<String, ({List<String> ids, List<String> fields})> selections,
      ) async {
        if (metadata case final BeaconMetadataReader sql) {
          final result = <String, Object?>{};
          for (final MapEntry(key: alias, value: selection)
              in selections.entries) {
            final rows = await sql.read(
              viewer,
              selection.ids,
              selection.fields,
            );
            result[alias] = selection.ids.length == 1
                ? rows.singleOrNull
                : rows;
          }
          return result;
        }
        final fields = <String>[];
        for (final MapEntry(key: alias, value: selection)
            in selections.entries) {
          final ids = selection.ids.map(jsonEncode);
          final arguments = selection.ids.length == 1
              ? 'beacon_by_pk(id: ${ids.single})'
              : 'beacon(where: {id: {_in: [${ids.join(', ')}]}})';
          fields.add('$alias: $arguments { ${selection.fields.join(' ')} }');
        }
        return query(viewer, 'query { ${fields.join(' ')} }');
      }

      final postBeforeBud = (await read(_carol, {'post': post}))['post'];
      expect(postBeforeBud, containsPair('id', _post));
      expect(postBeforeBud, containsPair('can_read_content', true));
      expectChildCounts(postBeforeBud, 0, 'Carol before budding');

      final child = await fixture.bud();
      await fixture.writer.execute('''
INSERT INTO public.beacon_participant
  (beacon_id, user_id, role, status, room_access)
VALUES ('$child', '$_helper', 0, 0, 3)
''');

      // Bob can fork the Request he was invited to. Its derivative is a
      // separate Request, and Bob shares it with Carol.
      final fork = await fixture.beacons.createBeacon(
        authorId: _bob,
        title: 'Arrange garden access',
        status: BeaconStatus.open,
        isDiscoverable: false,
        lineageParentBeaconId: child,
        lineageRootBeaconId: child,
      );
      await fixture.writer.execute(
        Sql.named('''
UPDATE public.beacon SET published_at = now() WHERE id = @fork
'''),
        parameters: {'fork': fork.id},
      );
      await fixture.writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (beacon_id, sender_id, recipient_id)
VALUES (@fork, '$_bob', '$_carol')
'''),
        parameters: {'fork': fork.id},
      );

      Future<Map<String, Object?>> reads(String viewer) => read(viewer, {
        'bud': (
          ids: [child],
          fields: [
            'id',
            'title',
            'description',
            ...accessFields,
            ...lineageFields,
          ],
        ),
        'post': post,
        'visible': (
          ids: [_post, child],
          fields: ['id', ...accessFields, ...lineageFields],
        ),
        'fork': (ids: [fork.id], fields: ['id', ...lineageFields]),
      });

      List<String> visibleIds(Map<String, Object?> data) {
        if (data['visible'] case final List<Object?> rows) {
          return [
            for (final row in rows)
              switch (row) {
                {'id': final String id} => id,
                _ => throw StateError('Invalid visible beacon row: $row'),
              },
          ];
        }
        throw StateError('Missing visible beacon rows: $data');
      }

      final carol = await reads(_carol);
      final violations = metadata?.privacyViolations ?? const <String>[];
      final metadataError =
          'Unsafe Hasura permissions: ${violations.join(', ')}';
      expect(
        carol['bud'],
        isNull,
        reason: [
          'Carol must not be able to read the bud Request',
          if (violations.isNotEmpty) metadataError,
        ].join('\n'),
      );
      expect(violations, isEmpty, reason: metadataError);

      final bob = await reads(_bob);
      expect(
        visibleIds(bob),
        unorderedEquals([_post, child]),
      );
      expectChildCounts(bob['post'], 1, 'Bob');
      expect(bob['bud'], containsPair('title', _title));
      expect(bob['bud'], containsPair('can_read_content', true));
      expect(bob['bud'], containsPair('lineage_parent_beacon_id', null));
      expect(bob['bud'], containsPair('lineage_root_beacon_id', null));
      expect(
        bob['post'],
        containsPair('post_root_message_id', PostBudPrivacyFixture.postRoot),
      );
      expect(bob['fork'], {
        'id': fork.id,
        'lineage_parent_beacon_id': child,
        'lineage_root_beacon_id': child,
      });

      final helper = await reads(_helper);
      expect(helper['bud'], containsPair('title', _title));
      expect(helper['post'], isNull);
      expect(
        jsonEncode(helper['bud']),
        isNot(contains(PostBudPrivacyFixture.postBody)),
      );
      final helperParent = await fixture.hierarchy.loadParentReference(
        childBeaconId: child,
        viewerId: _helper,
      );
      expect(helperParent.title, isNull);
      final bobParent = await fixture.hierarchy.loadParentReference(
        childBeaconId: child,
        viewerId: _bob,
      );
      expect(bobParent.state, BeaconParentReferenceState.available);
      expect(bobParent.beaconId, _post);
      expect(bobParent.isPost, isTrue);

      expect(
        carol['post'],
        postBeforeBud,
        reason: 'The Post projection and access fields reveal no change',
      );
      expect(visibleIds(carol), [_post]);
      expectChildCounts(carol['post'], 0, 'Carol');
      expect(carol['fork'], containsPair('id', fork.id));
      expect(
        jsonEncode(carol),
        isNot(contains(child)),
        reason:
            'Sharing the fork must not reveal the unreadable source Request',
      );
    },
  );
}

Future<Iterable<String>> _hasuraBeaconFields(
  Future<Map<String, Object?>> Function(String, String) query,
  RegExp childField,
) async {
  // Inspect the schema as a user, so any exposed child counts are exercised.
  final schema = await query(_carol, '''
query {
  beacon: __type(name: "beacon") { fields { name } }
  root: __schema { queryType { fields { name } } }
}
''');
  List<String> fieldNames(Object? type) {
    if (type case {'fields': final List<Object?> fields}) {
      return [
        for (final field in fields)
          switch (field) {
            {'name': final String name} => name,
            _ => throw StateError('Invalid schema field: $field'),
          },
      ];
    }
    throw StateError('Invalid schema type: $type');
  }

  final root = switch (schema['root']) {
    {'queryType': final Object? type} => type,
    _ => throw StateError('Missing Hasura root query type'),
  };
  expect(
    fieldNames(root).where(
      (field) =>
          field == 'beacon_aggregate' ||
          (field.contains('beacon') && childField.hasMatch(field)),
    ),
    isEmpty,
    reason: 'Any beacon aggregate needs an authenticated child-count check',
  );
  return fieldNames(schema['beacon']);
}

final class _UnusedUsers extends Fake implements UserRepositoryPort {}

final class _UnusedInvitations extends Fake
    implements InvitationRepositoryPort {}
