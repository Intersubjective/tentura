import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
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
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/domain/use_case/invite_accepted_setup_case.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../features/block/support/controllable_block_case.dart';
import '../../support/test_realtime_sync.dart';

final class _Accounts implements AttentionAccountPort {
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get currentAccountChanges => _changes.stream;

  void emit(String accountId) => _changes.add(accountId);

  Future<void> close() => _changes.close();
}

final class _Repository extends AttentionRepositoryFake {
  _Repository(this.feed);

  AttentionFeed feed;

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async =>
      feed;

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
  _FakeSetupPort({this.batchResult = const {}});

  Map<String, InviteSeedPromptState> batchResult;

  @override
  Future<Map<String, InviteSeedPromptState>> fetchPrompts(
    Set<String> subjectIds,
  ) async =>
      Map<String, InviteSeedPromptState>.from(batchResult);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AttentionReceipt _inviteReceipt({
  required String id,
  required String subjectId,
  DateTime? createdAt,
}) =>
    AttentionReceipt(
      id: id,
      category: 'connections',
      kind: 'inviteAccepted',
      priority: 'normal',
      title: 'Joined $subjectId',
      body: 'Body',
      actionUrl: '/profile/view/$subjectId',
      createdAt: createdAt ?? DateTime.now().subtract(const Duration(days: 1)),
      collapsedCount: 1,
      presentationKey: 'invite_accepted',
      presentationPayloadJson: '{"inviteOrigin":"new_account"}',
      surface: AttentionSurface.activity,
      actorUserId: subjectId,
      targetEntityId: subjectId,
    );

InviteSeedPromptState _pendingPrompt(String subjectId) =>
    InviteSeedPromptState(
      inviterUserId: 'inviter-1',
      inviteeUserId: subjectId,
      state: PromptStateValue.pending,
    );

UpdatesFeedState _stateWithProjections({
  required List<AttentionReceipt> items,
  required Map<String, PromptProjection> projections,
}) =>
    UpdatesFeedState(
      items: items,
      promptProjections: projections,
      summary: AttentionSummary(unreadTotal: items.length),
    );

Future<void> _drain([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
}

Widget _wrap(Widget child) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(800, 800)),
    child: TenturaResponsiveScope(
      child: MaterialApp(
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  final now = DateTime(2026, 9, 10, 12);

  group('computeInvitePromptPinPlacement', () {
    test('one fresh pending prompt pins once', () {
      final receipt = _inviteReceipt(id: 'r1', subjectId: 's1');
      final placement = computeInvitePromptPinPlacement(
        items: [receipt],
        state: _stateWithProjections(
          items: [receipt],
          projections: {'s1': PromptProjection.known(_pendingPrompt('s1'))},
        ),
        now: now,
      );
      expect(placement.pinnedReceipts.map((r) => r.id), ['r1']);
      expect(placement.collapsedCount, 0);
      expect(placement.liftedReceiptIds, {'r1'});
    });

    test('two fresh pending prompts pin twice', () {
      final r1 = _inviteReceipt(id: 'r1', subjectId: 's1');
      final r2 = _inviteReceipt(id: 'r2', subjectId: 's2');
      final placement = computeInvitePromptPinPlacement(
        items: [r1, r2],
        state: _stateWithProjections(
          items: [r1, r2],
          projections: {
            's1': PromptProjection.known(_pendingPrompt('s1')),
            's2': PromptProjection.known(_pendingPrompt('s2')),
          },
        ),
        now: now,
      );
      expect(placement.pinnedReceipts.length, 2);
      expect(placement.collapsedCount, 0);
    });

    test('three fresh pending prompts collapse with N = 3 and no pins', () {
      final receipts = [
        _inviteReceipt(id: 'r1', subjectId: 's1'),
        _inviteReceipt(id: 'r2', subjectId: 's2'),
        _inviteReceipt(id: 'r3', subjectId: 's3'),
      ];
      final placement = computeInvitePromptPinPlacement(
        items: receipts,
        state: _stateWithProjections(
          items: receipts,
          projections: {
            for (final r in receipts)
              r.actorUserId!: PromptProjection.known(
                _pendingPrompt(r.actorUserId!),
              ),
          },
        ),
        now: now,
      );
      expect(placement.pinnedReceipts, isEmpty);
      expect(placement.collapsedCount, 3);
      expect(placement.liftedReceiptIds.length, 3);
    });

    test('boundary flips between two pins and collapsed at three', () {
      final two = [
        _inviteReceipt(id: 'r1', subjectId: 's1'),
        _inviteReceipt(id: 'r2', subjectId: 's2'),
      ];
      final three = [
        ...two,
        _inviteReceipt(id: 'r3', subjectId: 's3'),
      ];
      final projections = {
        's1': PromptProjection.known(_pendingPrompt('s1')),
        's2': PromptProjection.known(_pendingPrompt('s2')),
        's3': PromptProjection.known(_pendingPrompt('s3')),
      };
      final atTwo = computeInvitePromptPinPlacement(
        items: two,
        state: _stateWithProjections(items: two, projections: projections),
        now: now,
      );
      final atThree = computeInvitePromptPinPlacement(
        items: three,
        state: _stateWithProjections(items: three, projections: projections),
        now: now,
      );
      expect(atTwo.pinnedReceipts.length, 2);
      expect(atTwo.collapsedCount, 0);
      expect(atThree.pinnedReceipts, isEmpty);
      expect(atThree.collapsedCount, 3);
    });

    test('equal timestamps order by receipt id descending', () {
      final stamp = DateTime(2026, 9, 9);
      final rA = _inviteReceipt(id: 'r-a', subjectId: 's1', createdAt: stamp);
      final rB = _inviteReceipt(id: 'r-z', subjectId: 's2', createdAt: stamp);
      final placement = computeInvitePromptPinPlacement(
        items: [rA, rB],
        state: _stateWithProjections(
          items: [rA, rB],
          projections: {
            's1': PromptProjection.known(_pendingPrompt('s1')),
            's2': PromptProjection.known(_pendingPrompt('s2')),
          },
        ),
        now: now,
      );
      expect(placement.pinnedReceipts.map((r) => r.id), ['r-z', 'r-a']);
    });

    test('unknown projection stays chronological', () {
      final receipt = _inviteReceipt(id: 'r1', subjectId: 's1');
      final placement = computeInvitePromptPinPlacement(
        items: [receipt],
        state: _stateWithProjections(
          items: [receipt],
          projections: const {},
        ),
        now: now,
      );
      expect(placement.liftedReceiptIds, isEmpty);
    });

    test('settled projection reinserts into chronology', () {
      final receipt = _inviteReceipt(id: 'r1', subjectId: 's1');
      final placement = computeInvitePromptPinPlacement(
        items: [receipt],
        state: _stateWithProjections(
          items: [receipt],
          projections: {
            's1': PromptProjection.known(
              _pendingPrompt('s1').copyWith(state: PromptStateValue.skipped),
            ),
          },
        ),
        now: now,
      );
      expect(placement.liftedReceiptIds, isEmpty);
    });

    test('stale pending prompt is not lifted', () {
      final receipt = _inviteReceipt(
        id: 'r1',
        subjectId: 's1',
        createdAt: now.subtract(const Duration(days: 8)),
      );
      final placement = computeInvitePromptPinPlacement(
        items: [receipt],
        state: _stateWithProjections(
          items: [receipt],
          projections: {'s1': PromptProjection.known(_pendingPrompt('s1'))},
        ),
        now: now,
      );
      expect(placement.liftedReceiptIds, isEmpty);
    });
  });

  group('UpdatesFeedPane pinning UI', () {
    Future<UpdatesFeedCubit> _mountFeed(
      WidgetTester tester, {
      required List<AttentionReceipt> items,
      required Map<String, InviteSeedPromptState> prompts,
    }) async {
      final accounts = _Accounts();
      final feed = AttentionFeed(
        summary: AttentionSummary(unreadTotal: items.length),
        page: AttentionFeedPage(items: items),
      );
      final repository = _Repository(feed);
      final sync = buildTestRealtimeSync();
      final attention = AttentionCase(
        repository,
        accounts,
        sync.case_,
        noopBlockCase(),
        FeedSessionRegistry(),
        Logger('prompt-pinning'),
      );
      accounts.emit('viewer');
      await _drain();

      final setup = _FakeSetupPort(batchResult: prompts);
      final cubit = UpdatesFeedCubit(
        destinationId: AttentionFeedDestinationId.activityStream,
        attention: attention,
        setup: setup,
        realtime: sync.case_,
        logger: Logger('prompt-pinning-cubit'),
      );
      await _drain(24);

      await tester.pumpWidget(
        _wrap(
          BlocProvider.value(
            value: cubit,
            child: const UpdatesFeedPane(showViewControl: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return cubit;
    }

    testWidgets('renders one pinned row for a single fresh pending prompt', (
      tester,
    ) async {
      final receipt = _inviteReceipt(id: 'r1', subjectId: 's1');
      final cubit = await _mountFeed(
        tester,
        items: [receipt],
        prompts: {'s1': _pendingPrompt('s1')},
      );

      expect(
        find.byKey(TestIds.key(TestIds.activityPromptPin('r1'))),
        findsOneWidget,
      );
      expect(
        find.byKey(TestIds.key(TestIds.activityPromptCollapsed)),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(cubit.close());
    });

    testWidgets('renders collapsed row for three fresh pending prompts', (
      tester,
    ) async {
      final items = [
        _inviteReceipt(id: 'r1', subjectId: 's1'),
        _inviteReceipt(id: 'r2', subjectId: 's2'),
        _inviteReceipt(id: 'r3', subjectId: 's3'),
      ];
      final cubit = await _mountFeed(
        tester,
        items: items,
        prompts: {
          's1': _pendingPrompt('s1'),
          's2': _pendingPrompt('s2'),
          's3': _pendingPrompt('s3'),
        },
      );

      expect(
        find.byKey(TestIds.key(TestIds.activityPromptCollapsed)),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('activity-prompt-pin-r1')), findsNothing);
      expect(find.textContaining('3 people joined'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      unawaited(cubit.close());
    });
  });
}
