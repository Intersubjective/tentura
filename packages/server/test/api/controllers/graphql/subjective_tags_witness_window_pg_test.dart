@Tags(['pg', 'multi-connection'])
library;

import 'dart:async';
import 'dart:convert';

import 'package:shelf_plus/shelf_plus.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_capability_projection.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/capability_projection_case.dart';
import 'package:tentura_server/domain/use_case/capability_routing_case.dart';
import 'package:tentura_server/domain/use_case/forward_band_case.dart';
import 'package:tentura_server/env.dart';

import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNull, isNotNull;
import 'package:tentura_server/data/repository/witness_window_repository.dart';

import '../../../domain/use_case/capability_projection_case_mocks.mocks.dart';
import '../../../domain/use_case/capability_routing_case_mocks.mocks.dart'
    hide MockRoutingMutePort;
import '../../../domain/use_case/forward_band_case_mocks.mocks.dart';

import '../../../support/disposable_pg_target.dart';

const _ego = 'Utagswindowego01';
const _witness = 'Utagswindowpeer01';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SUBJECTIVE_TAGS_WINDOW_TEST_DB',
    defaultNamePrefix: 'tentura_test_subjective_tags_window',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  for (final concurrent in [false, true]) {
    test(
      concurrent
          ? 'concurrent SubjectiveTags reads preserve one witness window and return tags'
          : 'repeated SubjectiveTags reads create and refresh one initially absent witness window',
      () async {
        final session = await setUpDisposablePgWriter(target: target);
        addTearDown(() => tearDownDisposablePgWriter(session: session));
        final pg = target.databaseEnv;
        final env = Env(
          environment: Environment.test,
          pgHost: pg.pgHost,
          pgPort: pg.pgPort,
          pgDatabase: pg.pgDatabase,
          pgUsername: pg.pgUsername,
          pgPassword: pg.pgPassword,
          maxConnectionCount: 1,
          constellationDbMaxConcurrent: 1,
          printEnv: false,
          isDebugModeOn: false,
        );
        final database = TenturaDb(env);
        addTearDown(database.close);
        // Independent Drift instances and pools prevent transaction admission in
        // one instance from serializing requests from separate server workers.
        final otherDatabase = TenturaDb(env);
        addTearDown(otherDatabase.close);
        final repositories = [
          WitnessWindowRepository(database),
          WitnessWindowRepository(otherDatabase),
        ];
        final storageErrors = <Object>[];
        final writer = session.writer;
        for (final id in [_ego, _witness]) {
          await writer.execute(
            'INSERT INTO public."user" (id, display_name, public_key) '
            "VALUES ('$id', '$id', '$id-key')",
          );
        }
        // Model slow storage so two cache-miss writes overlap. This trigger adds
        // latency only; it does not manufacture a constraint violation or alter data.
        await writer.execute(r'''
CREATE FUNCTION public.slow_witness_window_insert() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_sleep(0.5);
  RETURN NEW;
END;
$$
''');
        await writer.execute('''
CREATE TRIGGER slow_witness_window_insert
BEFORE INSERT ON public.ego_witness_window
FOR EACH ROW EXECUTE FUNCTION public.slow_witness_window_insert()
''');
        final bothCacheMisses = Completer<void>();
        var cacheMisses = 0;
        var explicitlyTrusted = true;
        GraphqlController controllerFor(WitnessWindowRepository repository) {
          final witnessWindow = MockWitnessWindowPort();
          final cellPort = MockCapabilityCellPort();
          final ownEvidencePort = MockCapabilityOwnEvidencePort();
          final routingMute = MockRoutingMutePort();
          final pairBlockQuery = MockPairBlockQueryPort();
          final personVisibility = MockPersonVisibilityRepositoryPort();
          final userBlock = MockUserBlockRepositoryPort();
          final bandCandidatePort = MockBandCandidatePort();
          final beaconRepositoryPort = MockBeaconRepositoryPort();
          final guard = MockBeaconAccessGuard();
          final capabilityEvidence = MockCapabilityEvidencePort();
          final projectionCase = CapabilityProjectionCase(
            witnessWindow,
            cellPort,
            ownEvidencePort,
            routingMute,
            pairBlockQuery,
            personVisibility,
            userBlock,
            env: env,
            logger: Logger('SubjectiveTagsWitnessWindowTest'),
          );
          final forwardBandCase = ForwardBandCase(
            bandCandidatePort,
            beaconRepositoryPort,
            projectionCase,
            guard,
            env: Env(environment: Environment.test),
            logger: Logger('QueryCapabilityProjectionBandTest'),
          );
          final routingCase = CapabilityRoutingCase(
            capabilityEvidence,
            routingMute,
            env: Env(environment: Environment.test),
            logger: Logger('QueryCapabilityProjectionRoutingTest'),
          );
          final query = QueryCapabilityProjection(
            capabilityProjectionCase: projectionCase,
            forwardBandCase: forwardBandCase,
            capabilityRoutingCase: routingCase,
          );

          when(
            ownEvidencePort.fetchTombstones(
              egoId: anyNamed('egoId'),
              subjectIds: anyNamed('subjectIds'),
            ),
          ).thenAnswer((_) async => const []);
          when(
            pairBlockQuery.blockedPairsAmong(userIds: anyNamed('userIds')),
          ).thenAnswer((_) async => const {});
          when(
            routingMute.mutedSlugsFor(subjectIds: anyNamed('subjectIds')),
          ).thenAnswer((_) async => const {});
          when(
            witnessWindow.cachedWindow(
              egoId: anyNamed('egoId'),
              normalizedContext: anyNamed('normalizedContext'),
            ),
          ).thenAnswer(
            (invocation) async {
              final cached = await repository.cachedWindow(
                egoId: invocation.namedArguments[#egoId] as String,
                normalizedContext:
                    invocation.namedArguments[#normalizedContext] as String,
              );
              if (concurrent && cached.isEmpty) {
                cacheMisses++;
                if (cacheMisses == 2) bothCacheMisses.complete();
                // Neither request may compute/store until BOTH real lookups
                // have returned an empty cache on independent connections.
                await bothCacheMisses.future;
              }
              return cached;
            },
          );
          when(
            witnessWindow.storeWindow(
              egoId: anyNamed('egoId'),
              normalizedContext: anyNamed('normalizedContext'),
              weights: anyNamed('weights'),
            ),
          ).thenAnswer(
            (invocation) async {
              try {
                await repository.storeWindow(
                  egoId: invocation.namedArguments[#egoId] as String,
                  normalizedContext:
                      invocation.namedArguments[#normalizedContext] as String,
                  weights:
                      invocation.namedArguments[#weights]
                          as List<WitnessWeight>,
                );
              } on Object catch (error) {
                storageErrors.add(error);
                rethrow;
              }
            },
          );
          // Fix the upstream MeritRank input; cache reads and writes remain real PG.
          when(
            witnessWindow.rawWindowFacts(
              egoId: anyNamed('egoId'),
              normalizedContext: anyNamed('normalizedContext'),
              topK: anyNamed('topK'),
            ),
          ).thenAnswer((_) async {
            return RawWindowFacts(
              topPeers: [
                RawPeerFact(
                  peerId: _witness,
                  forwardMr: 0.5,
                  explicitlyTrusted: explicitlyTrusted,
                ),
              ],
              trustedScores: explicitlyTrusted ? [0.5] : [],
            );
          });
          when(
            cellPort.fetchCells(
              subjectIds: anyNamed('subjectIds'),
              tagSlugs: anyNamed('tagSlugs'),
              admittedWitnesses: anyNamed('admittedWitnesses'),
            ),
          ).thenAnswer((_) async => const []);

          when(
            userBlock.isBlockedPair(a: anyNamed('a'), b: anyNamed('b')),
          ).thenAnswer((_) async => false);
          // Read one's own profile to avoid unrelated visibility-policy fixtures.
          when(
            ownEvidencePort.fetchOwnEvidence(
              egoId: anyNamed('egoId'),
              subjectIds: anyNamed('subjectIds'),
              tagSlugs: anyNamed('tagSlugs'),
            ),
          ).thenAnswer(
            (_) async => const [
              OwnEvidenceRow(
                subjectUserId: _ego,
                tagSlug: 'transport',
                channel: EvidenceChannel.outcome,
              ),
            ],
          );
          return GraphqlController(
            env,
            schema: TenturaGraphQL(
              GraphQLSchema(
                queryType: GraphQLObjectType('Query', 'Query root')
                  ..fields.add(query.subjectiveTags),
              ),
            ),
          );
        }

        final controllers = repositories.map(controllerFor).toList();
        Future<Map<String, dynamic>> readTags(int worker) async {
          final controller = controllers[worker];
          final response = await controller.handler(
            Request(
              'POST',
              Uri.parse('http://localhost/api/v2/graphql'),
              headers: {'content-type': 'application/json'},
              context: {kGlobalInputQueryJwt: const JwtEntity(sub: _ego)},
              body: jsonEncode({
                'operationName': 'SubjectiveTags',
                'query':
                    'query SubjectiveTags { subjectiveTags(targetId: "$_ego") '
                    '{ subjectUserId tagSlug tier } }',
              }),
            ),
          );
          expect(response.statusCode, 200);
          return jsonDecode(await response.readAsString())
              as Map<String, dynamic>;
        }

        Future<DateTime> expectStoredWindow({bool admitted = true}) async {
          final rows = await writer.execute('''
SELECT w.ego_user_id, w.context, w.witness_user_id, w.m, w.admitted,
       w.computed_at, w.mr_epoch = e.epoch AS current_epoch,
       w.computed_at > now() - interval '1 minute' AS fresh
FROM public.ego_witness_window w CROSS JOIN public.mr_publish_epoch e
''');
          expect(rows, hasLength(1));
          final values = rows.single.toColumnMap();
          final computedAt = values.remove('computed_at')! as DateTime;
          expect(values, {
            'ego_user_id': _ego,
            'context': '',
            'witness_user_id': _witness,
            'm': 1.0,
            'admitted': admitted,
            'current_epoch': true,
            'fresh': true,
          });
          return computedAt;
        }

        // Each case begins with no row, independently of the other test.
        expect(
          await writer.execute('SELECT 1 FROM public.ego_witness_window'),
          isEmpty,
        );
        final responses = <Map<String, dynamic>>[];
        if (concurrent) {
          responses.addAll(await Future.wait([readTags(0), readTags(1)]));
          expect(cacheMisses, 2);
          await expectStoredWindow();
        } else {
          responses.add(await readTags(0));
          final firstComputedAt = await expectStoredWindow();
          explicitlyTrusted = false;
          // Expire the first write so the second sequential request must write
          // the same key again instead of taking the warm-cache fast path.
          await writer.execute(
            "UPDATE public.ego_witness_window SET computed_at = now() - interval '1 day'",
          );
          responses.add(await readTags(0));
          final secondComputedAt = await expectStoredWindow(admitted: false);
          expect(
            secondComputedAt.isAfter(firstComputedAt),
            isTrue,
            reason: 'The repeated write must replace the earlier computation',
          );
        }
        for (final response in responses) {
          final wire = jsonEncode(response);
          for (final privateDetail in [
            '23505',
            '25P02',
            'ego_witness_window',
            'duplicate key',
            'violates unique constraint',
          ]) {
            expect(wire, isNot(contains(privateDetail)));
          }
          expect(
            response,
            {
              'data': {
                'subjectiveTags': [
                  {
                    'subjectUserId': _ego,
                    'tagSlug': 'transport',
                    'tier': 'ownOutcome',
                  },
                ],
              },
            },
            reason:
                'Every request must succeed. '
                'Storage failures: $storageErrors',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
