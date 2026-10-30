import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:auto_route/auto_route.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:tentura/data/repository/attention_repository.dart';
import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_view/data/repository/beacon_display_repository.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/my_work/data/repository/my_work_repository.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/screen/home_screen.dart';
import 'package:tentura/features/home/ui/bloc/home_activation_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_attention_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/data/repository/posts_repository.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_operational_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../data/service/remote_api_client/retry_later_wire_support.dart';
import '../../support/test_realtime_sync.dart';
import '../beacon_plan/beacon_plan_test_support.dart';
import '../block/support/controllable_block_case.dart';
import 'my_work_test_support.dart';
import '../../ui/effect/fake_ui_effect_port.dart';

// These enrichments consume membership IDs, not one another's responses.
const _enrichmentFields = {
  'myWorkLastActivityEvent',
  'InboxRoomContextBatch',
  'beaconDisplayStatuses',
};
// These home projections do not consume one another's results. Membership
// itself follows obligations because it needs the obligation IDs.
const _initialFields = {'inbox_item', 'myPosts', 'liveObligationBeacons'};
const _serverFields = {
  ..._enrichmentFields,
  'liveObligationBeacons',
  'closureState',
  'myWorkAttention',
  'myPosts',
  'attentionMarkers',
};

void main() {
  testWidgets(
    'authenticated home root batches or overlaps independent startup reads',
    (tester) async {
      await tester.runAsync(() async {
        final blocked = Completer<void>();
        final release = Completer<void>();
        final initialBlocked = Completer<void>();
        final releaseInitial = Completer<void>();
        var clock = 0;
        final calls = <({Set<String> fields, String path, int start})>[];
        final completions = <int>[];
        final server = MockClient((request) async {
          if (request.url.path.endsWith('/session/access-token')) {
            return jsonResponse({
              'subject': 'u1',
              'access_token': 'test-token',
              'expires_in': 3600,
            });
          }
          final body = jsonDecode(request.body);
          // Accept HTTP array batches and operations selecting multiple fields;
          // neither operation names nor the number of HTTP posts is fixed.
          final operations = body is List ? body : [body];
          final selections = [
            for (final operation in operations)
              _rootFields(operation as Map<String, dynamic>),
          ];
          final fields = {
            for (final selected in selections)
              for (final field in selected) field.name.value,
          };
          calls.add((fields: fields, path: request.url.path, start: clock++));
          if (fields.intersection(_initialFields).isNotEmpty) {
            if (!initialBlocked.isCompleted) initialBlocked.complete();
            await releaseInitial.future;
          }
          final enrichment = fields.intersection(_enrichmentFields).isNotEmpty;
          if (enrichment) {
            if (!blocked.isCompleted) blocked.complete();
            // Hold EVERY independent enrichment response. A serial client
            // cannot advance to its next read. A concurrent/batched client can
            // dispatch the entire wave before any response is released.
            await release.future;
            completions.add(clock++);
          }
          final responses = [
            for (final selected in selections)
              {
                'data': {
                  '__typename': 'query_root',
                  for (final field in selected)
                    (field.alias?.value ?? field.name.value): _fieldData(field),
                },
              },
          ];
          return http.Response(
            jsonEncode(body is List ? responses : responses.single),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        await withRemote(server, (remote) async {
          await GetIt.I.reset();
          final realtime = buildTestRealtimeSync();
          final block = noopBlockCase();
          // Auth/session restoration is complete when the authenticated root
          // mounts. Domain account-change background refreshes are quiescent.
          final attention = AttentionCase(
            AttentionRepository(remote),
            _NoAccountChanges(),
            realtime.case_,
            block,
            FeedSessionRegistry(),
            Logger('root-startup-attention'),
            qaLatencyMeasurementEnabled: false,
          );
          final homeAttention = HomeAttentionCubit(
            attention,
            _SignedInAccount(),
            Logger('root-startup-markers'),
          );
          final activation = HomeActivationCubit(_OrientationPreferences());
          final operational = InboxOperationalCubit();
          final reselect = HomeTabReselectCubit();
          final effects = FakeUiEffectPort();
          final screen = ScreenCubit(effects);
          final beacon = FakeBeaconRepository();
          final forward = _ShellForwardRepository();
          final room = FakeBeaconThreadsRepository();
          final roomCase = buildTestBeaconThreadsCase(
            FakeRoomHints(),
            roomRepo: room,
          );
          final hints = BeaconRoomHintsRepository(remote);
          final inboxRepository = InboxRepository(remote, hints);
          final signal = BookkeepingRefreshSignal();
          final work = MyWorkCase(
            MyWorkRepository(remote),
            FakeArchiveRepository(),
            forward,
            beacon,
            roomCase,
            hints,
            BeaconDisplayRepository(remote),
            ClosureRepository(remote),
            realtime.case_,
            signal,
            attention,
            FakeBeaconPlanRepository(BeaconPlan.decode(planJson())),
            env: const Env(),
            logger: Logger('root-startup-work'),
          );
          GetIt.I
            ..registerSingleton<AuthCubit>(_AuthenticatedAuth())
            ..registerSingleton<ScreenCubit>(screen)
            ..registerSingleton<HomeTabReselectCubit>(reselect)
            ..registerSingleton<HomeAttentionCubit>(homeAttention)
            ..registerSingleton<HomeActivationCubit>(activation)
            ..registerSingleton<InboxOperationalCubit>(operational)
            ..registerSingleton<UiEffectPort>(effects)
            ..registerSingleton<MyWorkCase>(work)
            ..registerSingleton<InboxCase>(
              InboxCase(
                inboxRepository,
                roomCase,
                forward,
                realtime.case_,
                signal,
                block,
                env: const Env(),
                logger: Logger('root-startup-inbox'),
              ),
            )
            ..registerSingleton<PostsCase>(
              PostsCase(
                PostsRepository(remote),
                realtime.case_,
                env: const Env(),
                logger: Logger('root-startup-posts'),
              ),
            );
          final router = _HomeStartupRouter();
          late Set<String> beforeRelease;
          late int releaseAt;
          late Set<String> initialBeforeRelease;
          late int initialReleaseAt;
          try {
            await tester.pumpWidget(
              MaterialApp.router(routerConfig: router.config()),
            );
            await tester.pump();
            try {
              await initialBlocked.future.timeout(const Duration(seconds: 5));
              await tester.pump();
              await Future<void>.delayed(Duration.zero);
              initialBeforeRelease = {for (final call in calls) ...call.fields};
              initialReleaseAt = clock++;
            } finally {
              releaseInitial.complete();
            }
            try {
              await blocked.future.timeout(const Duration(seconds: 5));
              await tester.pump();
              await Future<void>.delayed(Duration.zero);
              beforeRelease = {for (final call in calls) ...call.fields};
              releaseAt = clock++;
            } finally {
              release.complete();
            }
            final context = tester.element(find.byType(_HomeStartupBody));
            final cubit = context.read<MyWorkCubit>();
            if (!cubit.state.attentionLoaded && cubit.state.loadError == null) {
              await cubit.stream
                  .firstWhere((s) => s.attentionLoaded || s.loadError != null)
                  .timeout(const Duration(seconds: 5));
            }
            final inbox = context.read<InboxCubit>();
            if (!inbox.state.projectionLoaded &&
                !inbox.state.projectionFailed) {
              await inbox.stream
                  .firstWhere((s) => s.projectionLoaded || s.projectionFailed)
                  .timeout(const Duration(seconds: 5));
            }
            final posts = context.read<PostsCubit>();
            await tester.pump();
            if (!posts.state.loaded) {
              await posts.stream
                  .firstWhere((s) => s.loaded)
                  .timeout(const Duration(seconds: 5));
            }
            await Future<void>.delayed(Duration.zero);
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(router.currentPath, '/');
            expect(cubit.state.loadError, isNull);
            final card = cubit.state.nonArchivedCards.single;
            expect(card.role, MyWorkCardRole.authored);
            expect(card.beacon.author.id, 'u1');
            expect(card.lastActivityEvent?.event.id, 'event1');
            expect(card.roomCurrentLine, 'Waiting for a response');
            expect(card.displayStatus?.canCancel, isTrue);
            // Closure and attention may follow enrichment; their ordering is
            // not a concurrency requirement of this test.
            expect(card.showCloseNowCta, isTrue);
            expect(cubit.state.attentionByBeacon['b1']?.unseenCount, 2);
            expect(inbox.state.projectionLoaded, isTrue);
            expect(inbox.state.projectionFailed, isFalse);
            expect(posts.state.active.single.id, 'post1');
            expect(find.text('Prepare the workshop'), findsOneWidget);
            expect(find.text('Workshop conversation'), findsOneWidget);
            expect(effects.emitted, isEmpty);
            final observed = {for (final call in calls) ...call.fields};
            // Presence guards make routing checks non-vacuous. Every server
            // field used in this root scenario (including live obligations)
            // must go to V2; Hasura membership and Inbox stay on V1.
            expect(observed, containsAll(_serverFields));
            for (final call in calls) {
              if (call.fields.intersection(_serverFields).isNotEmpty) {
                expect(call.path, '/api/v2/graphql', reason: '${call.fields}');
              }
              if (call.fields.contains('beacon') ||
                  call.fields.contains('inbox_item')) {
                expect(call.path, '/api/v1/graphql', reason: '${call.fields}');
              }
            }
            expect(completions, everyElement(greaterThan(releaseAt)));
            expect(
              initialBeforeRelease,
              containsAll(_initialFields),
              reason:
                  'The authenticated root must start Inbox, Conversations, '
                  'and obligations without waiting for another projection response',
            );
            expect(
              calls
                  .where(
                    (call) =>
                        call.fields.intersection(_initialFields).isNotEmpty,
                  )
                  .map((call) => call.start),
              everyElement(lessThan(initialReleaseAt)),
            );
            expect(
              calls
                  .where(
                    (call) =>
                        call.fields.intersection(_enrichmentFields).isNotEmpty,
                  )
                  .map((call) => call.start),
              everyElement(lessThan(releaseAt)),
              reason:
                  'Every independent enrichment must start before any '
                  'enrichment response is released',
            );
            expect(
              beforeRelease,
              containsAll(_enrichmentFields),
              reason:
                  'The root startup must dispatch independent card reads '
                  'concurrently or batched, before any enrichment response completes',
            );
          } finally {
            if (!releaseInitial.isCompleted) releaseInitial.complete();
            if (!release.isCompleted) release.complete();
            await tester.pumpWidget(const SizedBox.shrink());
            router.dispose();
            await homeAttention.close();
            await attention.dispose();
            await activation.close();
            await operational.close();
            await reselect.close();
            await screen.close();
            await inboxRepository.dispose();
            await beacon.dispose();
            await forward.dispose();
            await room.dispose();
            await GetIt.I.reset();
          }
        });
      });
    },
  );
}

// Keep the production HomeScreen.wrappedRoute and its account-scoped startup
// providers/reporters. Replace only navigation chrome and tab presentation
// with a small projection of the same loaded state.
class _HomeStartupBody extends HomeScreen {
  const _HomeStartupBody();

  @override
  Widget build(BuildContext context) {
    final work = context.watch<MyWorkCubit>().state;
    final posts = context.watch<PostsCubit>().state;
    return Column(
      children: [
        for (final card in work.nonArchivedCards) Text(card.beacon.title),
        for (final post in posts.active) Text(post.rootExcerpt),
      ],
    );
  }
}

class _HomeStartupRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      path: '/',
      initial: true,
      page: PageInfo(
        'HomeStartup',
        builder: (_) => const WrappedRoute(child: _HomeStartupBody()),
      ),
    ),
  ];
}

class _AuthenticatedAuth extends Fake implements AuthCubit {
  @override
  AuthState get state =>
      AuthState(currentAccountId: 'u1', updatedAt: DateTime(2026));
  @override
  Stream<AuthState> get stream => const Stream.empty();
}

class _NoAccountChanges implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

class _SignedInAccount implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => Stream.value('u1');
}

class _ShellForwardRepository extends FakeForwardRepository {
  @override
  Stream<String> get forwardCommandCompleted => const Stream.empty();
}

class _OrientationPreferences extends Fake
    implements HomeOrientationPreferencesPort {
  @override
  Future<bool> isActivated({required String userId}) async => true;
  @override
  Future<bool> isOrientationDismissed({required String userId}) async => true;
  @override
  Future<OrientationDebugOverride> getDebugOverride() async =>
      OrientationDebugOverride.auto;
}

List<FieldNode> _rootFields(Map<String, dynamic> operation) {
  final document = parseString(operation['query'] as String);
  final name = operation['operationName'];
  final definition = document.definitions
      .whereType<OperationDefinitionNode>()
      .firstWhere((d) => name == null || d.name?.value == name);
  final fragments = {
    for (final f in document.definitions.whereType<FragmentDefinitionNode>())
      f.name.value: f,
  };
  List<FieldNode> expand(SelectionSetNode selection) => [
    for (final node in selection.selections)
      if (node is FieldNode)
        node
      else if (node is InlineFragmentNode)
        ...expand(node.selectionSet)
      else if (node is FragmentSpreadNode)
        ...expand(fragments[node.name.value]!.selectionSet),
  ];
  return expand(definition.selectionSet);
}

Object? _fieldData(FieldNode field) => switch (field.name.value) {
  '__typename' => 'query_root',
  'liveObligationBeacons' => <String>[],
  'inbox_item' => [],
  'attentionMarkers' => {
    '__typename': 'v2_AttentionMarkers',
    'unreadBeaconIds': ['b1'],
  },
  'myPosts' => [
    {
      '__typename': 'v2_PostSummary',
      'id': 'post1',
      'authorId': 'u1',
      'authorName': 'Workshop author',
      'authorAvatar': '',
      'rootExcerpt': 'Workshop conversation',
      'lastMessageIsRoot': true,
      'mutedForever': false,
      'unreadCount': 1,
      'isAuthor': true,
      'status': 0,
      'lastActivityAt': '2026-10-20T12:00:00Z',
    },
  ],
  'beacon' =>
    field.alias?.value == 'obligationBeacons' ? [] : [_authoredRequest],
  'beacon_help_offer' || 'beacon_archived' => [],
  'myWorkLastActivityEvent' => [
    {
      '__typename': 'v2_MyWorkLastActivityEventRow',
      'beaconId': 'b1',
      'id': 'event1',
      'type': 1,
      'createdAt': '2026-10-20T12:00:00Z',
    },
  ],
  'InboxRoomContextBatch' => [
    {
      '__typename': 'v2_InboxRoomContextRow',
      'beaconId': 'b1',
      'isRoomMember': true,
      'roomUnreadCount': 0,
      'currentLine': 'Waiting for a response',
    },
  ],
  'beaconDisplayStatuses' => [
    {
      '__typename': 'v2_BeaconDisplayStatus',
      'beaconId': 'b1',
      'status': 5,
      'phase': 'coordinating',
      'suggestedAction': 'none',
      'slot2Kind': 'none',
      'tier': 'coordination',
      'canCancel': true,
      'canDelete': false,
      'everAcknowledgedCommitterCount': 0,
    },
  ],
  'closureState' => {
    '__typename': 'v2_ClosureState',
    'epoch': 1,
    'status': 5,
    'role': 'author',
    'members': [],
    'closesAt': '2026-11-01T12:00:00Z',
    'canCloseNow': true,
  },
  'myWorkAttention' => [
    {
      '__typename': 'v2_MyWorkBeaconAttention',
      'beaconId': 'b1',
      'unseenCount': 2,
      'liveObligations': [],
    },
  ],
  _ => throw StateError('No fixture for GraphQL field ${field.name.value}'),
};

// A wrapping-up Request authored by the signed-in viewer exercises status,
// closure, and attention reads as well as the initial Hasura membership read.
final _authoredRequest = <String, Object?>{
  '__typename': 'beacon',
  'id': 'b1',
  'title': 'Prepare the workshop',
  'description': '',
  'needs': '',
  'tags': '',
  'status': 5,
  'kind': 0,
  'forward_policy': 0,
  'cover_source': 0,
  'is_discoverable': true,
  'created_at': '2026-10-20T12:00:00Z',
  'updated_at': '2026-10-20T12:00:00Z',
  'status_changed_at': '2026-10-20T12:00:00Z',
  'beacon_images': [],
  'help_offers': [],
  'active_help_offers': [],
  'participant_help_offers': [],
  'admitted_helpers': [],
  'help_offers_aggregate': _countAggregate('beacon_help_offer'),
  'unanswered_help_offers': _countAggregate('beacon_help_offer'),
  'admitted_helpers_aggregate': _countAggregate('beacon_admitted_helper'),
  'author': {
    '__typename': 'user',
    'id': 'u1',
    'display_name': 'Workshop author',
    'description': '',
    'scores': [],
  },
};

Map<String, Object?> _countAggregate(String type) => {
  '__typename': '${type}_aggregate',
  'aggregate': {'__typename': '${type}_aggregate_fields', 'count': 0},
};
