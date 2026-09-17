import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import '../../support/attention_repository_fake_base.dart';
import 'package:tentura/domain/capability/invite_seed_prompt_state.dart';
import 'package:tentura/domain/capability/prompt_state_value.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import '../../support/noop_attention_actor_profiles.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository extends AttentionRepositoryFake {
  final pendingFetches = <Completer<AttentionFeed>>[];

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) => pendingFetches.removeAt(0).future;

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async => {};

  @override
  Future<Set<String>> liveObligationBeacons() async => const {};

  @override
  Future<int> markAllSeen({AttentionSurface? surface}) async => 0;

  @override
  Future<int> markSeen(List<String> ids) async => 0;

  @override
  Future<int> markUnseen(List<String> ids) async => 0;

  @override
  Future<int> settle({required String receiptId, required String kind}) async =>
      0;
}

final class _FakeSetupPort implements InviteAcceptedSetupPort {
  _FakeSetupPort({this.batchResult = const {}, this.throwOnBatch = false});

  Map<String, InviteSeedPromptState> batchResult;
  bool throwOnBatch;
  int batchCalls = 0;
  final Set<String> lastBatchIds = {};

  @override
  Future<Map<String, InviteSeedPromptState>> fetchPrompts(
    Set<String> subjectIds,
  ) async {
    batchCalls++;
    lastBatchIds
      ..clear()
      ..addAll(subjectIds);
    if (throwOnBatch) throw StateError('offline');
    return Map<String, InviteSeedPromptState>.from(batchResult);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AttentionReceipt _inviteReceipt({String id = 'receipt-invite-1'}) =>
    AttentionReceipt(
      id: id,
      category: 'connections',
      kind: 'inviteAccepted',
      priority: 'normal',
      title: 'Joined',
      body: 'Body',
      actionUrl: '/profile/view/invitee-1',
      createdAt: DateTime.utc(2026, 8, 4),
      collapsedCount: 1,
      presentationKey: 'invite_accepted',
      presentationPayloadJson: '{"inviteOrigin":"new_account"}',
      surface: AttentionSurface.activity,
      actorUserId: 'invitee-1',
      targetEntityId: 'invitee-1',
    );

AttentionFeed _feed(List<AttentionReceipt> items) => AttentionFeed(
  summary: const AttentionSummary(unreadTotal: 1),
  page: AttentionFeedPage(items: items),
);

Future<void> _pump([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('RealtimeEntityKind.fromWire', () {
    test('decodes invite_seed_prompt wire vocabulary', () {
      expect(
        RealtimeEntityKind.fromWire('invite_seed_prompt'),
        RealtimeEntityKind.inviteSeedPrompt,
      );
    });
  });

  group('UpdatesFeedCubit prompt projection', () {
    late _Accounts accounts;
    late _Repository repository;
    late TestRealtimeSyncPort realtime;
    late RealtimeSyncCase realtimeSync;
    late _FakeSetupPort setup;
    late AttentionCase attention;
    late UpdatesFeedCubit cubit;

    setUp(() {
      accounts = _Accounts();
      repository = _Repository();
      final sync = buildTestRealtimeSync();
      realtime = sync.port;
      realtimeSync = sync.case_;
      setup = _FakeSetupPort();
      attention = AttentionCase(
        repository,
        accounts,
        sync.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('prompt-projection-test'),
      );
    });

    tearDown(() async {
      await cubit.close();
      await attention.dispose();
      await realtime.dispose();
      await accounts.close();
    });

    test('feed renders while batch prompt fetch fails', () async {
      final initial = Completer<AttentionFeed>();
      repository.pendingFetches.add(initial);
      setup.throwOnBatch = true;
      cubit = UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.activityStream,
        attention: attention,
        setup: setup,
        realtime: realtimeSync,
        logger: Logger('prompt-projection-test'),
        actorProfiles: buildNoopAttentionActorProfiles(),
      );
      accounts.emit('account-a');
      await _pump();
      initial.complete(_feed([_inviteReceipt()]));
      await _pump();

      expect(cubit.state.items, hasLength(1));
      expect(cubit.state.status, isA<StateIsSuccess>());
      expect(
        cubit.state.promptProjectionFor('invitee-1'),
        const PromptProjection.failed(),
      );
      expect(cubit.state.canPinInvitePrompt(_inviteReceipt()), isFalse);
    });

    test('known pending state is a pinning candidate', () async {
      final initial = Completer<AttentionFeed>();
      repository.pendingFetches.add(initial);
      setup.batchResult = {
        'invitee-1': const InviteSeedPromptState(
          inviterUserId: 'inviter-1',
          inviteeUserId: 'invitee-1',
          state: PromptStateValue.pending,
        ),
      };
      cubit = UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.activityStream,
        attention: attention,
        setup: setup,
        realtime: realtimeSync,
        logger: Logger('prompt-projection-test'),
        actorProfiles: buildNoopAttentionActorProfiles(),
      );
      accounts.emit('account-a');
      await _pump();
      initial.complete(_feed([_inviteReceipt()]));
      await _pump();

      expect(cubit.state.canPinInvitePrompt(_inviteReceipt()), isTrue);
    });

    test('unknown projection is never treated as settled for pinning', () {
      const projection = PromptProjection.unknown();
      expect(projection.isKnownSettled, isFalse);
      expect(
        isInvitePromptPinCandidate(
          receipt: _inviteReceipt(),
          projection: projection,
        ),
        isFalse,
      );
    });

    test('invalidation envelope converges a mounted subject', () async {
      final initial = Completer<AttentionFeed>();
      repository.pendingFetches.add(initial);
      setup.batchResult = {
        'invitee-1': const InviteSeedPromptState(
          inviterUserId: 'inviter-1',
          inviteeUserId: 'invitee-1',
          state: PromptStateValue.pending,
        ),
      };
      cubit = UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.activityStream,
        attention: attention,
        setup: setup,
        realtime: realtimeSync,
        logger: Logger('prompt-projection-test'),
        actorProfiles: buildNoopAttentionActorProfiles(),
      );
      accounts.emit('account-a');
      await _pump();
      initial.complete(_feed([_inviteReceipt()]));
      await _pump();
      expect(
        cubit.state.promptProjectionFor('invitee-1').isKnownPending,
        isTrue,
      );

      setup.batchResult = {
        'invitee-1': const InviteSeedPromptState(
          inviterUserId: 'inviter-1',
          inviteeUserId: 'invitee-1',
          state: PromptStateValue.skipped,
        ),
      };
      final wireKind = RealtimeEntityKind.fromWire('invite_seed_prompt');
      expect(wireKind, RealtimeEntityKind.inviteSeedPrompt);
      realtime.emitChange(
        RealtimeEntityChange(
          kind: wireKind!,
          aggregateId: 'invitee-1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
        ),
      );
      await _pump();

      expect(
        cubit.state.promptProjectionFor('invitee-1').isKnownSettled,
        isTrue,
      );
      expect(cubit.state.canPinInvitePrompt(_inviteReceipt()), isFalse);
    });
  });
}
