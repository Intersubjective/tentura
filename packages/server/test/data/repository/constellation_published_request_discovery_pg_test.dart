@Tags(['pg', 'mr'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_constellation_field_requests.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_repository.dart';
import 'package:tentura_server/data/repository/constellation_field_requests_repository.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/port/image_object_gc_port.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/use_case/beacon_case.dart';
import 'package:tentura_server/domain/use_case/constellation_field_requests_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_lifecycle_effects_test_support.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_child_create_port.dart';
import '../../support/noop_commitment_query_case.dart';

const _viewerId = 'Ufieldviewer1';
const _authorId = 'Ufieldauthor1';

// Supplementary server diagnostics, separate from the client acceptance
// tests. A failing authenticated query identifies a pre-existing server
// blocker; it must not be reported as a failing client merge regression.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PUBLISHED_REQUEST_DISCOVERY_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_pub_discovery',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late Connection listener;
  late StreamSubscription<String> subscription;
  late BeaconCase beacons;
  late ConstellationFieldRequestsRepository targeted;
  late ConstellationFieldRepository field;
  final itemHints = <Map<String, dynamic>>[];

  setUpAll(() async {
    session = await setUpDisposablePgWriter(
      target: target,
      createPgmer2Extension: true,
    );
    db = openDisposablePgDatabase(target);
    for (final id in [_viewerId, _authorId]) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key, now(), now())
'''),
        parameters: {'id': id, 'key': 'pk-$id'},
      );
    }
    await session.writer.execute('''
INSERT INTO public.vote_user (subject, object, amount)
VALUES ('$_viewerId', '$_authorId', 1), ('$_authorId', '$_viewerId', 1)
''');
    beacons = BeaconCase(
      BeaconRepository(db),
      _UnusedImages(),
      _UnusedImageGc(),
      _UnusedTasks(),
      noopCommitmentQueryCase(),
      BeaconAccessRepository(db),
      BeaconHierarchyRepository(db),
      FakeBeaconChildCreatePort(),
      buildLifecycleEffectsCase(),
      env: Env(environment: Environment.test),
      logger: Logger('PublishedRequestDiscoveryTest'),
    );
    targeted = ConstellationFieldRequestsRepository(db);
    // The direct discoverable scan needs no profile lookup.
    field = ConstellationFieldRepository(db, _UnusedProfiles());
    listener = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    await listener.execute('LISTEN entity_changes');
    subscription = listener.channels['entity_changes'].listen((payload) {
      final hint = jsonDecode(payload) as Map<String, dynamic>;
      if (hint['entity'] == 'constellation_item') itemHints.add(hint);
    });
  });

  tearDownAll(() async {
    await subscription.cancel();
    await listener.close();
    await tearDownDisposablePgWriter(session: session, drift: db);
  });

  setUp(() async {
    await session.writer.execute(
      Sql.named('DELETE FROM public.beacon WHERE user_id = @author'),
      parameters: {'author': _authorId},
    );
    itemHints.clear();
  });

  Future<Map<String, dynamic>> receiveItemHint(String beaconId) async {
    for (var i = 0; i < 100; i++) {
      final matches = itemHints
          .where((hint) => hint['id'] == beaconId)
          .toList();
      if (matches.isNotEmpty) {
        expect(matches, hasLength(1));
        expect(matches.single['event'], 'insert');
        expect(matches.single['user_ids'], contains(_viewerId));
        return matches.single;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('No constellation_item notification received for $beaconId');
  }

  test('publishing without sending makes a discoverable Request immediately '
      'available to a mutual contact through both Field reads', () async {
    // This is the standalone Request publish path. No forward edge, offer,
    // participant, or readability stub grants access to the viewer.
    final draft = await beacons.create(
      userId: _authorId,
      title: 'Published without sending',
      description: 'A new Request for my contacts to discover',
      draft: true,
      isDiscoverable: true,
    );
    expect(draft.status, BeaconStatus.draft);
    final published = await beacons.publishDraft(
      userId: _authorId,
      beaconId: draft.id,
    );

    // Read at once, without a navigation-triggered reload or a retry.
    final targetedRows = await targeted.discoverableRequestsByIds(
      viewerId: _viewerId,
      beaconIds: {published.id},
      filters: ConstellationFieldMembershipFilters.defaults,
    );
    final fullRows = await field.discoverableRequests(
      viewerId: _viewerId,
      context: '',
      cap: 100,
    );

    expect(published.status, BeaconStatus.open);
    expect(published.publishedAt, isNotNull);
    expect(
      targetedRows.map((row) => row.id).toList(),
      [published.id],
      reason:
          'The item read must return the just-published discoverable Request; '
          'full discovery returned ${fullRows.map((row) => row.id).toList()}.',
    );
    expect(fullRows.map((row) => row.id).toList(), [published.id]);
    expect(targetedRows.single.authorId, _authorId);
    expect(targetedRows.single.title, published.title);
    expect(targetedRows.single.viewerHasForwardEdge, isFalse);
    expect(targetedRows.single.viewerHasActiveHelpOffer, isFalse);
    expect(targetedRows.single.viewerIsRoomParticipant, isFalse);
    expect(
      (await session.writer.execute(
        Sql.named(
          'SELECT count(*) FROM public.beacon_forward_edge '
          'WHERE beacon_id = @id',
        ),
        parameters: {'id': published.id},
      )).single.single,
      0,
    );

    // Supplementary PG producer contract, separate from the immediate reads:
    // this checks the emitted id and recipient, not WebSocket/client adoption.
    final hint = await receiveItemHint(published.id);
    expect(hint['id'], published.id);

    final privateDraft = await beacons.create(
      userId: _authorId,
      title: 'Kept off the Field',
      description: 'Published with discoverability disabled',
      draft: true,
      isDiscoverable: false,
    );
    final privateRequest = await beacons.publishDraft(
      userId: _authorId,
      beaconId: privateDraft.id,
    );
    final privateRows = await targeted.discoverableRequestsByIds(
      viewerId: _viewerId,
      beaconIds: {privateRequest.id},
      filters: ConstellationFieldMembershipFilters.defaults,
    );
    expect(privateRows, isEmpty);
    final fullAfterPrivatePublish = await field.discoverableRequests(
      viewerId: _viewerId,
      context: '',
      cap: 100,
    );
    expect(fullAfterPrivatePublish.map((row) => row.id).toList(), [
      published.id,
    ]);
  });

  test('the authenticated targeted GraphQL query serializes a just-published '
      'Request with empty optional fields', () async {
    final draft = await beacons.create(
      userId: _authorId,
      title: 'A new Request without optional fields',
      description: 'Discoverable by my mutual contact',
      draft: true,
      isDiscoverable: true,
    );
    final published = await beacons.publishDraft(
      userId: _authorId,
      beaconId: draft.id,
    );
    final repositoryRows = await targeted.discoverableRequestsByIds(
      viewerId: _viewerId,
      beaconIds: {published.id},
      filters: ConstellationFieldMembershipFilters.defaults,
    );
    expect(repositoryRows.map((row) => row.id).toList(), [published.id]);
    // The query below is driven by a notification received from the real
    // publish trigger. This still covers the server boundary only; the
    // client wire and cubit tests separately cover decoding and adoption.
    final hint = await receiveItemHint(published.id);
    final hintedBeaconId = hint['id']! as String;
    final query = QueryConstellationFieldRequests(
      case_: ConstellationFieldRequestsCase(
        targeted,
        env: Env(environment: Environment.test),
        logger: Logger('PublishedRequestGraphQLTest'),
      ),
    );
    final graphQL = TenturaGraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', null)..fields.addAll(query.all),
      ),
      customTypes: customTypes,
    );
    final response = await graphQL.parseAndExecute(
      r'''
      query ConstellationFieldRequestsFetch(
        $ids: [String!]!
        $showClosed: Boolean! = false
        $participatedOnly: Boolean! = false
      ) {
        constellationFieldRequests(
          ids: $ids
          showClosed: $showClosed
          participatedOnly: $participatedOnly
        ) {
          id authorId title status needs primaryNeedSlug startAt endAt
          addressLabel hasCoordinates isMine viewerHasActiveHelpOffer
          viewerIsRoomParticipant viewerHasForwardEdge helpOfferCount
          coverSource coverThumb { id } parentBeaconId
        }
      }''',
      // Use the variable types HTTP JSON decoding produces, including its
      // List<dynamic> for ids, rather than Dart-only typed collections.
      variableValues:
          jsonDecode(
                jsonEncode({
                  'ids': [hintedBeaconId],
                  'showClosed': false,
                  'participatedOnly': false,
                }),
              )
              as Map<String, dynamic>,
      globalVariables: {kGlobalInputQueryJwt: const JwtEntity(sub: _viewerId)},
    );
    expect(response, {
      'constellationFieldRequests': [
        {
          'id': published.id,
          'authorId': _authorId,
          'title': published.title,
          'status': 0,
          'needs': <String>[],
          'primaryNeedSlug': null,
          'startAt': null,
          'endAt': null,
          'addressLabel': null,
          'hasCoordinates': false,
          'isMine': false,
          'viewerHasActiveHelpOffer': false,
          'viewerIsRoomParticipant': false,
          'viewerHasForwardEdge': false,
          'helpOfferCount': 0,
          'coverSource': 0,
          'coverThumb': null,
          'parentBeaconId': null,
        },
      ],
    });
  });
}

class _UnusedImages extends Fake implements ImageRepositoryPort {}

class _UnusedImageGc extends Fake implements ImageObjectGcPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

class _UnusedProfiles extends Fake implements UserProfileBatchLookup {}
