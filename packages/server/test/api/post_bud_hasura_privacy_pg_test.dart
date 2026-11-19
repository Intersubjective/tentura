@Tags(['pg', 'repo-files'])
library;

import 'dart:convert';

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
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }
  final dockerAvailable = await IsolatedHasuraSession.isDockerAvailable();

  late PostBudPrivacyFixture fixture;
  late AuthCase auth;
  late IsolatedHasuraSession hasura;
  setUpAll(() async {
    final session = await setUpDisposablePgWriter(target: target);
    final database = openDisposablePgDatabase(target);
    addTearDown(
      () => tearDownDisposablePgWriter(session: session, drift: database),
    );
    fixture = PostBudPrivacyFixture(
      session.writer,
      database,
      target.databaseEnv,
    );
    final jwt = loadJwtKeysForHasuraPgTests();
    auth = AuthCase(
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
    hasura = await IsolatedHasuraSession.start(
      databaseEnv: target.databaseEnv,
      jwtPublicPem: jwt.publicKey,
    );
    addTearDown(hasura.stop);
    await hasura.applyRepoMetadata();
  });

  test(
    'Hasura reveals Request lineage only to viewers who can read its source',
    () async {
      await fixture.seedPost();
      Future<Map<String, dynamic>> query(String viewer, String document) async {
        final response = await http.post(
          Uri.parse('${hasura.baseUrl}/v1/graphql'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${auth.issueAccessToken(viewer).rawToken}',
          },
          body: jsonEncode({'query': document}),
        );
        expect(response.statusCode, 200);
        final wire = jsonDecode(response.body) as Map<String, dynamic>;
        expect(wire['errors'], isNull, reason: response.body);
        return wire['data'] as Map<String, dynamic>;
      }

      // Introspect the user role, which can select fewer fields than admin.
      // Include any child-count field it can actually select in the Post read.
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

      final childField = RegExp('child|descendant', caseSensitive: false);
      final countField = RegExp('count|total|number|num', caseSensitive: false);
      final childFields = fieldNames(
        schema['beacon'],
      ).where(childField.hasMatch).toList();
      final childCounts = childFields.where(countField.hasMatch).toList();
      expect(
        childFields.where((field) => !childCounts.contains(field)),
        isEmpty,
        reason:
            'Any exposed child relationship needs an authenticated privacy check',
      );
      final root = (schema['root'] as Map<String, dynamic>)['queryType'];
      expect(
        fieldNames(root).where(
          (field) =>
              field == 'beacon_aggregate' ||
              (field.contains('beacon') && childField.hasMatch(field)),
        ),
        isEmpty,
        reason: 'Any beacon aggregate needs an authenticated child-count check',
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

      const accessFields = '''
    can_read_content can_read_involvement can_read_admitted_helpers
    access_level access_reasons
''';
      final postSelection =
          '''
  post: beacon_by_pk(id: "$_post") {
    id title description post_root_message_id $accessFields ${childCounts.join(' ')}
  }
''';
      final postBeforeBud = (await query(
        _carol,
        'query { $postSelection }',
      ))['post'];
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

      Future<Map<String, dynamic>> reads(String viewer) => query(
        viewer,
        '''
query {
  bud: beacon_by_pk(id: "$child") {
    id title description $accessFields
    lineage_parent_beacon_id lineage_root_beacon_id
  }
  $postSelection
  visible: beacon(where: {id: {_in: ["$_post", "$child"]}}) {
    id $accessFields
    lineage_parent_beacon_id lineage_root_beacon_id
  }
  fork: beacon_by_pk(id: "${fork.id}") {
    id lineage_parent_beacon_id lineage_root_beacon_id
  }
}
''',
      );

      List<String> visibleIds(Map<String, dynamic> data) => [
        for (final row in data['visible'] as List)
          (row as Map<String, dynamic>)['id'] as String,
      ];

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

      final carol = await reads(_carol);
      expect(
        carol['post'],
        postBeforeBud,
        reason: 'The Post projection and access fields reveal no change',
      );
      expect(carol['bud'], isNull);
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
    skip: dockerAvailable ? false : 'Docker not available',
  );
}

final class _UnusedUsers extends Fake implements UserRepositoryPort {}

final class _UnusedInvitations extends Fake
    implements InvitationRepositoryPort {}
