// The «Для вас» invite card's state (plan D3): a pinned row with `inviteId`
// carries its invite; «Принять» / «Не смогу» take the row out of the pinned
// zone at once and put it back, with its invite, when the server refuses.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/feed_session_registry.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/port/attention_account_port.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/activity_offers_cubit.dart';
import 'package:tentura/domain/entity/author_invite.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'author_invite_test_support.dart';

import '../../support/test_realtime_sync.dart';
import '../block/support/controllable_block_case.dart';
import 'activity_offers_test_support.dart';
import 'inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;

Future<void> _settle([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.microtask(() {});
  }
  await Future<void>.delayed(const Duration(milliseconds: 60));
}

InboxItem _offer(String beaconId, DateTime at) =>
    InboxItem(beaconId: beaconId, latestForwardAt: at);

final class _Accounts implements AttentionAccountPort {
  @override
  Stream<String> get currentAccountChanges => const Stream.empty();
}

class _AttentionRepo extends ConfigurableActivityOffersAttentionRepo {
  Set<String> unread = const {};

  @override
  Future<AttentionFeed> fetch({
    required AttentionView view,
    String? cursor,
    String? search,
    int limit = 50,
    AttentionSurface? surface,
  }) async => const AttentionFeed(
    summary: AttentionSummary(),
    page: AttentionFeedPage(),
  );

  @override
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) async =>
      unread.intersection(beaconIds);

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

final class _ForwardRepo implements ForwardRepository {
  final _helpOfferChanges = StreamController<HelpOfferEvent>.broadcast();
  final _forwardChanges = StreamController<String>.broadcast();
  final _forwardCommandCompleted = StreamController<String>.broadcast();

  @override
  Stream<HelpOfferEvent> get helpOfferChanges => _helpOfferChanges.stream;

  @override
  Stream<String> get forwardChanges => _forwardChanges.stream;

  @override
  Stream<String> get forwardCommandCompleted => _forwardCommandCompleted.stream;

  void emitDeskChange(String beaconId) => _forwardChanges.add(beaconId);

  void emitHelpOffer(HelpOfferEvent event) => _helpOfferChanges.add(event);

  @override
  Future<void> dispose() async {
    await _helpOfferChanges.close();
    await _forwardChanges.close();
    await _forwardCommandCompleted.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeInboxRepository repo;
  late _ForwardRepo forwardRepo;
  late _AttentionRepo attentionRepo;
  late FakeAuthorInvitePort invitePort;
  late FakeUiEffectPort effects;
  late ActivityOffersCubit cubit;

  const inviter = Profile(id: 'Uinviter', displayName: 'Oleg');
  final at = DateTime.utc(2026, 10, 11, 12);

  ActivityOffersCubit buildCubit() {
    final sync = buildTestRealtimeSync();
    final attentionCase = AttentionCase(
      attentionRepo,
      _Accounts(),
      sync.case_,
      noopBlockCase(),
      FeedSessionRegistry(),
      Logger('activity-invite-test'),
    );
    final inboxCase = buildTestInboxCase(
      repo,
      buildTestBeaconThreadsCase(),
      forwardRepository: forwardRepo,
      realtimeSyncCase: sync.case_,
    );
    return ActivityOffersCubit(
      userId: 'u1',
      inboxCase: inboxCase,
      attentionCase: attentionCase,
      actorProfiles: buildActorProfiles(const [inviter]),
      authorInviteCase: buildAuthorInviteCase(invitePort),
      effects: effects,
    );
  }

  /// Three pinned rows; the middle one carries invite `I1`.
  Future<void> loadWithInvite() async {
    final items = [_offer('B1', at), _offer('B2', at), _offer('B3', at)];
    wireActivityOffersV2(inbox: repo, attention: attentionRepo, items: items);
    attentionRepo.offerRows = [
      for (final item in items)
        activityOfferSortRow(
          item,
        ).copyWith(inviteId: item.beaconId == 'B2' ? 'I1' : null),
    ];
    invitePort.pending = [
      PendingAuthorInvite(
        id: 'I1',
        beaconId: 'B2',
        beaconTitle: 'Ladder for Saturday',
        inviterId: inviter.id,
        createdAt: at,
        note: 'You have a ladder',
      ),
    ];
    cubit = buildCubit();
    await cubit.loadFirst();
    await _settle();
  }

  List<String> ids() => [for (final i in cubit.state.items) i.beaconId];

  setUp(() {
    repo = FakeInboxRepository();
    forwardRepo = _ForwardRepo();
    attentionRepo = _AttentionRepo();
    invitePort = FakeAuthorInvitePort();
    effects = FakeUiEffectPort();
  });

  tearDown(() async {
    await cubit.close();
    await forwardRepo.dispose();
    await repo.dispose();
  });

  test('a row with inviteId carries its invite, inviter and note', () async {
    await loadWithInvite();

    expect(cubit.state.inviteIdByBeacon, {'B2': 'I1'});
    expect(cubit.state.invites['I1']?.note, 'You have a ladder');
    expect(cubit.state.inviters[inviter.id]?.displayName, 'Oleg');
  });

  test('accept: the row leaves the pinned zone before the server answers, '
      'and stays out', () async {
    await loadWithInvite();
    invitePort.gate = Completer<void>();

    final accepting = cubit.acceptInvite('B2');
    await _settle(2);
    expect(invitePort.accepted, ['I1']);
    expect(ids(), ['B1', 'B3']);
    expect(cubit.state.inviteIdByBeacon, isEmpty);

    invitePort.gate!.complete();
    await accepting;
    expect(ids(), ['B1', 'B3']);
    expect(effects.emitted, isEmpty);
  });

  for (final error in <Exception>[
    const AuthorInviteNotPendingException('withdrawn'),
    const AuthorInviteNotPendingException('expired'),
    const AuthorInviteRequestNotOpenException(),
  ]) {
    test('accept rolls back on ${error.runtimeType} ($error)', () async {
      await loadWithInvite();
      invitePort.error = error;

      await cubit.acceptInvite('B2');

      expect(ids(), ['B1', 'B2', 'B3']);
      expect(cubit.state.inviteIdByBeacon, {'B2': 'I1'});
      expect(
        effects.emitted.whereType<ShowError>().single.error,
        same(error),
      );
    });
  }

  test('decline: answers the invite and keeps the dialog note', () async {
    await loadWithInvite();

    await cubit.declineInvite('B2', message: 'Away that weekend');

    expect(invitePort.declined, ['I1']);
    expect(ids(), ['B1', 'B3']);
    expect(repo.lastSetStatus, (
      beaconId: 'B2',
      status: InboxItemStatus.rejected,
      rejectionMessage: 'Away that weekend',
    ));
  });

  test('decline with no note sends only the invite decline', () async {
    await loadWithInvite();

    await cubit.declineInvite('B2');

    expect(invitePort.declined, ['I1']);
    expect(repo.lastSetStatus, isNull);
  });

  test('decline rolls back when the invite was withdrawn', () async {
    await loadWithInvite();
    invitePort.error = const AuthorInviteNotPendingException();

    await cubit.declineInvite('B2', message: 'no');

    expect(ids(), ['B1', 'B2', 'B3']);
    expect(cubit.state.inviteIdByBeacon, {'B2': 'I1'});
    expect(repo.lastSetStatus, isNull);
    expect(effects.emitted.whereType<ShowError>(), hasLength(1));
  });

  test('a row without an invite is untouched by accept', () async {
    await loadWithInvite();

    await cubit.acceptInvite('B1');

    expect(invitePort.accepted, isEmpty);
    expect(ids(), ['B1', 'B2', 'B3']);
  });

  // #725 (QA 2026-10-26, step 5): the zone knows which Requests carry an
  // answered author invitation, so their plain card keeps the invitation's
  // words; a row that arrives live learns the same facts the page carries.
  group('#725 invitation facts', () {
    test('a row whose invitation was declined is marked', () async {
      final items = [_offer('B1', at), _offer('B2', at)];
      wireActivityOffersV2(inbox: repo, attention: attentionRepo, items: items);
      attentionRepo.offerRows = [
        for (final item in items)
          activityOfferSortRow(
            item,
          ).copyWith(declinedInvite: item.beaconId == 'B2'),
      ];
      cubit = buildCubit();
      await cubit.loadFirst();
      await _settle();

      expect(cubit.state.declinedInviteBeacons, {'B2'});
      expect(cubit.state.inviteIdByBeacon, isEmpty);
    });

    test('a reload whose row no longer says declined clears the mark '
        '(decline, re-invite, withdraw)', () async {
      final items = [_offer('B1', at), _offer('B2', at)];
      wireActivityOffersV2(inbox: repo, attention: attentionRepo, items: items);
      attentionRepo.offerRows = [
        for (final item in items)
          activityOfferSortRow(
            item,
          ).copyWith(declinedInvite: item.beaconId == 'B2'),
      ];
      cubit = buildCubit();
      await cubit.loadFirst();
      await _settle();
      expect(cubit.state.declinedInviteBeacons, {'B2'});

      // A failed reload keeps what the zone knew.
      attentionRepo.failActivityOffers = true;
      await cubit.loadFirst();
      await _settle();
      expect(cubit.state.declinedInviteBeacons, {'B2'});

      // The author invited again and withdrew it: the latest invite is no
      // longer a declined one, and the row says so.
      attentionRepo
        ..failActivityOffers = false
        ..offerRows = [for (final item in items) activityOfferSortRow(item)];
      await cubit.loadFirst();
      await _settle();
      expect(cubit.state.declinedInviteBeacons, isEmpty);
    });

    test('decline marks the Request; a refused decline does not', () async {
      await loadWithInvite();
      invitePort.error = const AuthorInviteNotPendingException();
      await cubit.declineInvite('B2');
      expect(cubit.state.declinedInviteBeacons, isEmpty);

      invitePort.error = null;
      await cubit.declineInvite('B2');
      expect(cubit.state.declinedInviteBeacons, {'B2'});
    });

    test(
      'a live arrival with a pending invite becomes the invite card',
      () async {
        await loadWithInvite();
        final arrival = _offer('B9', at);
        repo.openForwardByBeacon['B9'] = arrival;
        attentionRepo.offerRows = [
          ...attentionRepo.offerRows,
          activityOfferSortRow(arrival).copyWith(inviteId: 'I9'),
        ];
        invitePort.pending = [
          ...invitePort.pending,
          PendingAuthorInvite(
            id: 'I9',
            beaconId: 'B9',
            beaconTitle: 'Moving boxes',
            inviterId: inviter.id,
            createdAt: at,
          ),
        ];

        forwardRepo.emitDeskChange('B9');
        await _settle(20);
        await _settle(20);

        expect(ids().first, 'B9');
        expect(cubit.state.inviteIdByBeacon['B9'], 'I9');
        expect(cubit.state.invites['I9']?.beaconTitle, 'Moving boxes');
      },
    );

    test('a live row that no longer says declined clears the mark', () async {
      await loadWithInvite();
      await cubit.declineInvite('B2');
      expect(cubit.state.declinedInviteBeacons, {'B2'});

      // Re-invited and withdrawn meanwhile, then restored: the row answers
      // `declinedInvite: false`.
      repo.openForwardByBeacon['B2'] = _offer('B2', at);
      attentionRepo.offerRows = [
        for (final id in ['B1', 'B2', 'B3'])
          activityOfferSortRow(_offer(id, at)),
      ];
      forwardRepo.emitDeskChange('B2');
      await _settle(20);
      await _settle(20);

      expect(ids().first, 'B2');
      expect(cubit.state.declinedInviteBeacons, isEmpty);
    });

    test('a restored row with a declined invitation arrives marked', () async {
      await loadWithInvite();
      final arrival = _offer('B9', at);
      repo.openForwardByBeacon['B9'] = arrival;
      attentionRepo.offerRows = [
        ...attentionRepo.offerRows,
        activityOfferSortRow(arrival).copyWith(declinedInvite: true),
      ];

      forwardRepo.emitDeskChange('B9');
      await _settle(20);
      await _settle(20);

      expect(ids().first, 'B9');
      expect(cubit.state.declinedInviteBeacons, contains('B9'));
      expect(cubit.state.inviteIdByBeacon.containsKey('B9'), isFalse);
    });
  });
}
