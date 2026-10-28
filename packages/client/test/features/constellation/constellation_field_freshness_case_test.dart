import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/constellation_trust_badge.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_targeted_read_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_freshness_case.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura/features/like/domain/port/person_trust_writes_port.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

// #672 / #671: the field follows trust changes and new Requests of direct
// contacts without any FULL read — the viewer's own writes are patched in
// at once, a `relationship` hint costs one small relation read, a
// `constellation_item` hint one authorized Request read.

const _me = 'me';

ConstellationTrustEdgeEntity _e(String src, String dst, [int tier = 1]) =>
    ConstellationTrustEdgeEntity(src: src, dst: dst, tier: tier);

/// Lena: mutual. Omar: trusts me, I do not trust him. Noor: a contact node
/// (I trust her, she is outside my visible set).
ConstellationField _field({
  List<ConstellationTrustEdgeEntity>? edges,
  List<ConstellationRequest> requests = const [],
  List<ConstellationPerson> extraPeers = const [],
}) => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 23),
  context: '',
  peers: [
    const ConstellationPerson(id: 'lena', displayName: 'Lena'),
    const ConstellationPerson(id: 'omar', displayName: 'Omar'),
    const ConstellationPerson(
      id: 'noor',
      displayName: 'Noor',
      visible: false,
      contactOnly: true,
    ),
    ...extraPeers,
  ],
  edges:
      edges ??
      [
        _e(_me, 'lena'),
        _e('lena', _me),
        _e('omar', _me),
        _e(_me, 'noor'),
      ],
  requests: requests,
  directContactIds: const ['lena', 'noor'],
  anchorProjection: ConstellationAnchorProjection.empty,
);

ConstellationRequest _request(String id, String authorId) =>
    ConstellationRequest(id: id, authorId: authorId, title: id, status: 0);

/// Five visible people the viewer trusts directly (tier-1 edges viewer → p).
/// Someone whose trust was [withdrawn] has left the visible set.
const _crowdIds = ['p1', 'p2', 'p3', 'p4', 'p5'];

ConstellationField _crowdField({Set<String> withdrawn = const {}}) =>
    ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 23),
      context: '',
      peers: [
        for (final id in _crowdIds)
          if (!withdrawn.contains(id)) ConstellationPerson(id: id),
      ],
      edges: [
        for (final id in _crowdIds)
          if (!withdrawn.contains(id)) _e(_me, id),
      ],
      requests: const [],
      directContactIds: [
        for (final id in _crowdIds)
          if (!withdrawn.contains(id)) id,
      ],
      anchorProjection: ConstellationAnchorProjection.empty,
    );

final class _AccountPort implements ConstellationAccountPort {
  _AccountPort(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}

final class _Server implements ConstellationRepositoryPort {
  _Server(this.clock);

  final FakeClockPort clock;
  ConstellationField field = _field();
  var fullReads = 0;

  /// When each FULL started.
  final fullStartedAt = <DateTime>[];

  /// When set, the next FULL waits for it and returns the field as it was
  /// when the read started.
  Completer<void>? gate;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fullReads++;
    fullStartedAt.add(clock.now());
    final snapshot = field;
    final wait = gate;
    gate = null;
    if (wait != null) await wait.future;
    return snapshot;
  }
}

final class _TargetedReads implements ConstellationTargetedReadPort {
  final relationCalls = <Set<String>>[];
  final requestCalls = <Set<String>>[];
  final filtersSeen = <ConstellationFieldMembershipFilters>[];
  var relations = <ConstellationViewerRelation>[];
  var requests = <ConstellationRequest>[];

  @override
  Future<List<ConstellationViewerRelation>> readViewerRelations(
    Set<String> personIds,
  ) async {
    relationCalls.add(personIds);
    return [
      for (final r in relations)
        if (personIds.contains(r.personId)) r,
    ];
  }

  @override
  Future<List<ConstellationRequest>> fetchRequests(
    Set<String> beaconIds, {
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async {
    requestCalls.add(beaconIds);
    filtersSeen.add(membershipFilters);
    return [
      for (final r in requests)
        if (beaconIds.contains(r.id)) r,
    ];
  }
}

final class _TrustWrites implements PersonTrustWritesPort {
  final controller = StreamController<PersonTrustWrite>.broadcast();

  @override
  Stream<PersonTrustWrite> get personTrustWrites => controller.stream;
}

void main() {
  late BehaviorSubject<String> account;
  late FakeClockPort clock;
  late FakeWakeUpPort wakeUp;
  late ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) sync;
  late _Server server;
  late _TargetedReads reads;
  late _TrustWrites trustWrites;
  late ConstellationFieldStoreCase store;
  late ConstellationFieldFreshnessCase freshness;
  late StoreLease lease;

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> advance(Duration by) async {
    var left = by;
    while (left > Duration.zero) {
      final step = left > const Duration(milliseconds: 100)
          ? const Duration(milliseconds: 100)
          : left;
      clock.advance(step);
      wakeUp.elapse(step);
      await settle();
      left -= step;
    }
  }

  /// How long the latest FULL started after the one before it.
  Duration gapBeforeLatestFull() => server.fullStartedAt.last.difference(
    server.fullStartedAt[server.fullStartedAt.length - 2],
  );

  List<String> peerIds() => [for (final p in store.current.field!.peers) p.id];

  Map<String, ConstellationTrustBadge> badges() =>
      constellationTrustBadges(field: store.current.field!, viewerId: _me);

  setUp(() async {
    account = BehaviorSubject<String>.seeded(_me);
    clock = FakeClockPort(DateTime.utc(2026, 10, 23));
    wakeUp = FakeWakeUpPort();
    sync = buildTestRealtimeSync();
    server = _Server(clock);
    reads = _TargetedReads();
    trustWrites = _TrustWrites();
    store = ConstellationFieldStoreCase(
      server,
      _AccountPort(account.stream),
      clock,
      wakeUp,
      sync.case_,
      env: const Env.fromEnvironment(),
      logger: Logger('FreshnessTest'),
    );
    freshness = ConstellationFieldFreshnessCase(
      store,
      reads,
      trustWrites,
      sync.case_,
      wakeUp,
      clock,
      env: const Env.fromEnvironment(),
      logger: Logger('FreshnessTest'),
    );
    await settle();
    lease = store.lease();
    await store.requestRefresh(ConstellationRefreshReason.load);
    await settle();
    expect(server.fullReads, 1);
    // Past the urgent spacing, so a FULL asked for later is not delayed.
    await advance(const Duration(seconds: 3));
  });

  tearDown(() async {
    await freshness.dispose();
    await store.dispose();
    await trustWrites.controller.close();
    await account.close();
    await sync.port.dispose();
  });

  void hint(
    RealtimeEntityKind kind,
    String id, {
    String? actor,
    RealtimeOperation operation = RealtimeOperation.update,
  }) => sync.port.emitChange(
    RealtimeEntityChange(
      kind: kind,
      aggregateId: id,
      operation: operation,
      source: RealtimeChangeSource.serverInvalidation,
      actorUserId: actor,
    ),
  );

  group("the viewer's own trust write (#672)", () {
    test('trusting someone on the field turns their ring at once, with no '
        'read', () async {
      expect(badges()['omar'], ConstellationTrustBadge.theyTrust);

      trustWrites.controller.add((personId: 'omar', amount: 1));
      await settle();

      expect(badges()['omar'], ConstellationTrustBadge.mutual);
      expect(server.fullReads, 1);
      expect(reads.relationCalls, isEmpty);
    });

    test('untrusting a mutual contact leaves "they trust you" and drops them '
        'from the direct contacts', () async {
      trustWrites.controller.add((personId: 'lena', amount: 0));
      await settle();

      expect(badges()['lena'], ConstellationTrustBadge.theyTrust);
      expect(store.current.field!.directContactIds, isNot(contains('lena')));
      expect(server.fullReads, 1);
    });

    test('untrusting a contact node takes it off the field', () async {
      trustWrites.controller.add((personId: 'noor', amount: 0));
      await settle();

      final field = store.current.field!;
      expect(field.peers.map((p) => p.id), isNot(contains('noor')));
      expect(badges(), isNot(contains('noor')));
      expect(server.fullReads, 1);
    });

    test('a FULL that started before the write cannot bring the old ring '
        'back; the next FULL is the truth again', () async {
      final gate = server.gate = Completer<void>();
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await settle();
      expect(server.fullReads, 2);

      trustWrites.controller.add((personId: 'omar', amount: 1));
      await settle();
      expect(badges()['omar'], ConstellationTrustBadge.mutual);

      // The read that started before the write lands with the old edges.
      gate.complete();
      await settle();
      expect(badges()['omar'], ConstellationTrustBadge.mutual);

      // Another session withdrew it again; a FULL started now says so.
      server.field = _field();
      await advance(const Duration(seconds: 3));
      await store.requestRefresh(ConstellationRefreshReason.load);
      await settle();
      expect(server.fullReads, 3);
      expect(badges()['omar'], ConstellationTrustBadge.theyTrust);
    });

    test(
      'trusting someone not on the field asks for one urgent FULL',
      () async {
        trustWrites.controller.add((personId: 'stranger', amount: 1));
        await advance(const Duration(seconds: 3));

        expect(server.fullReads, 2);
      },
    );
  });

  group('a relationship hint about someone on the field (#672)', () {
    test(
      'reads just that relation once and patches the ring, no FULL',
      () async {
        reads.relations = [
          const ConstellationViewerRelation(
            personId: 'lena',
            viewerTrusts: true,
            trustsViewer: false,
          ),
        ];

        hint(RealtimeEntityKind.relationship, 'lena', actor: 'lena');
        hint(RealtimeEntityKind.relationship, 'lena', actor: 'lena');
        await advance(const Duration(milliseconds: 500));

        expect(reads.relationCalls, [
          {'lena'},
        ]);
        expect(badges()['lena'], ConstellationTrustBadge.youTrust);
        expect(server.fullReads, 1);
      },
    );

    test('the endpoint named only as the actor is read too', () async {
      // Kai's id sorts first, so the hint names Kai and carries Omar as the
      // actor; Omar is the other endpoint.
      reads.relations = [
        const ConstellationViewerRelation(
          personId: 'omar',
          viewerTrusts: false,
          trustsViewer: false,
        ),
      ];

      hint(RealtimeEntityKind.relationship, _me, actor: 'omar');
      await advance(const Duration(milliseconds: 500));

      expect(reads.relationCalls, [
        {'omar'},
      ]);
      expect(badges(), isNot(contains('omar')));
    });

    test("the viewer's own change made in another session (the hint names "
        'only the viewer) asks for one FULL', () async {
      hint(RealtimeEntityKind.relationship, _me, actor: _me);
      await advance(const Duration(seconds: 3));

      expect(reads.relationCalls, isEmpty);
      expect(server.fullReads, 2);
    });

    test("this session's own write echoed back reads nothing more", () async {
      trustWrites.controller.add((personId: 'omar', amount: 1));
      hint(RealtimeEntityKind.relationship, _me, actor: _me);
      await advance(const Duration(seconds: 3));

      expect(reads.relationCalls, isEmpty);
      expect(server.fullReads, 1);
      expect(badges()['omar'], ConstellationTrustBadge.mutual);
    });

    test('a hint about nobody on the field reads nothing', () async {
      hint(RealtimeEntityKind.relationship, 'x', actor: 'y');
      await advance(const Duration(seconds: 1));

      expect(reads.relationCalls, isEmpty);
      expect(server.fullReads, 1);
    });

    test('while the field is hidden nothing is read; it refreshes once when '
        'shown', () async {
      lease.setVisible(false);
      hint(RealtimeEntityKind.relationship, 'lena', actor: 'lena');
      await advance(const Duration(seconds: 1));
      expect(reads.relationCalls, isEmpty);
      expect(server.fullReads, 1);

      lease.setVisible(true);
      await settle();
      expect(server.fullReads, 2);
    });
  });

  group('a new discoverable Request of a direct contact (#671)', () {
    test('is fetched through the authorized read and added, no FULL', () async {
      reads.requests = [_request('req-new', 'lena')];

      hint(
        RealtimeEntityKind.constellationItem,
        'req-new',
        actor: 'lena',
        operation: RealtimeOperation.insert,
      );
      await advance(const Duration(milliseconds: 500));

      expect(reads.requestCalls, [
        {'req-new'},
      ]);
      expect(
        reads.filtersSeen.single,
        ConstellationFieldMembershipFilters.defaults,
      );
      expect(
        store.current.field!.requests.map((r) => r.id),
        contains('req-new'),
      );
      expect(server.fullReads, 1);
    });

    test('the hint alone adds nothing: an unreadable Request stays off the '
        'field', () async {
      reads.requests = const [];

      hint(
        RealtimeEntityKind.constellationItem,
        'req-secret',
        actor: 'lena',
        operation: RealtimeOperation.insert,
      );
      await advance(const Duration(milliseconds: 500));

      expect(reads.requestCalls, [
        {'req-secret'},
      ]);
      expect(store.current.field!.requests, isEmpty);
    });

    test('a field at its Request cap takes no additions', () async {
      server.field = _field().copyWith(requestsCapped: true);
      await store.requestRefresh(ConstellationRefreshReason.load);
      await settle();
      reads.requests = [_request('req-new', 'lena')];

      hint(
        RealtimeEntityKind.constellationItem,
        'req-new',
        actor: 'lena',
        operation: RealtimeOperation.insert,
      );
      await advance(const Duration(milliseconds: 500));

      expect(store.current.field!.requests, isEmpty);
    });

    test('a contact node has no content on the field: no read', () async {
      hint(
        RealtimeEntityKind.constellationItem,
        'req-noor',
        actor: 'noor',
        operation: RealtimeOperation.insert,
      );
      await advance(const Duration(milliseconds: 500));

      expect(reads.requestCalls, isEmpty);
    });

    test('a Request whose author is not on the field is not added', () async {
      reads.requests = [_request('req-far', 'far')];

      hint(
        RealtimeEntityKind.constellationItem,
        'req-far',
        operation: RealtimeOperation.insert,
      );
      await advance(const Duration(milliseconds: 500));

      expect(reads.requestCalls, hasLength(1));
      expect(store.current.field!.requests, isEmpty);
    });

    test(
      'an older FULL landing later keeps it; a newer FULL is the truth',
      () async {
        final gate = server.gate = Completer<void>();
        unawaited(store.requestRefresh(ConstellationRefreshReason.load));
        await settle();

        reads.requests = [_request('req-new', 'lena')];
        hint(
          RealtimeEntityKind.constellationItem,
          'req-new',
          actor: 'lena',
          operation: RealtimeOperation.insert,
        );
        await advance(const Duration(milliseconds: 500));
        expect(
          store.current.field!.requests.map((r) => r.id),
          contains('req-new'),
        );

        gate.complete();
        await settle();
        expect(
          store.current.field!.requests.map((r) => r.id),
          contains('req-new'),
        );

        // Closed meanwhile: the next FULL no longer has it.
        await advance(const Duration(seconds: 3));
        await store.requestRefresh(ConstellationRefreshReason.load);
        await settle();
        expect(store.current.field!.requests, isEmpty);
      },
    );
  });

  // A removed tier-1 edge between the viewer and someone on the field changes
  // who the viewer can see, so the visible-set content (not just the ring)
  // has to follow: one FULL, never closer than 10 s to the previous one.
  group('a removed tier-1 edge to someone on the field', () {
    final newcomer = [const ConstellationPerson(id: 'zed', displayName: 'Zed')];

    test("the viewer's own write turns the ring at once, then one FULL "
        'brings the visible set up to date no sooner than 10 s after the '
        'previous FULL', () async {
      server.field = _field(
        edges: [_e('lena', _me), _e('omar', _me), _e(_me, 'noor')],
        extraPeers: newcomer,
      );

      trustWrites.controller.add((personId: 'lena', amount: 0));
      await settle();

      expect(badges()['lena'], ConstellationTrustBadge.theyTrust);
      expect(server.fullReads, 1);

      // Not an ordinary urgent FULL (2 s): the spacing is 10 s.
      await advance(const Duration(seconds: 5));
      expect(server.fullReads, 1);
      // The visible set is only brought up to date by the spaced FULL.
      expect(peerIds(), isNot(contains('zed')));

      await advance(const Duration(seconds: 10));
      expect(server.fullReads, 2);
      expect(
        gapBeforeLatestFull(),
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
      expect(peerIds(), contains('zed'));
      expect(badges()['lena'], ConstellationTrustBadge.theyTrust);

      // And only that one.
      await advance(const Duration(seconds: 30));
      expect(server.fullReads, 2);
    });

    test('a relationship hint showing the viewer withdrew trust turns the '
        'ring, then one FULL brings the visible set up to date no sooner '
        'than 10 s after the previous FULL', () async {
      server.field = _field(
        edges: [_e('lena', _me), _e('omar', _me), _e(_me, 'noor')],
        extraPeers: newcomer,
      );
      reads.relations = [
        const ConstellationViewerRelation(
          personId: 'lena',
          viewerTrusts: false,
          trustsViewer: true,
        ),
      ];

      hint(RealtimeEntityKind.relationship, 'lena', actor: 'lena');
      await advance(const Duration(milliseconds: 500));

      expect(badges()['lena'], ConstellationTrustBadge.theyTrust);
      expect(server.fullReads, 1);

      await advance(const Duration(seconds: 5));
      expect(server.fullReads, 1);
      // The visible set is only brought up to date by the spaced FULL.
      expect(peerIds(), isNot(contains('zed')));

      await advance(const Duration(seconds: 10));
      expect(server.fullReads, 2);
      expect(
        gapBeforeLatestFull(),
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
      expect(peerIds(), contains('zed'));

      await advance(const Duration(seconds: 30));
      expect(server.fullReads, 2);
    });

    test('five removals within 10 s dispatch just one FULL, at least 10 s '
        'after the previous one, and the visible set follows it', () async {
      server.field = _crowdField();
      await store.requestRefresh(ConstellationRefreshReason.load);
      await settle();
      await advance(const Duration(seconds: 3));
      final before = server.fullReads;
      server.field = _crowdField(withdrawn: _crowdIds.toSet());

      // All five land well inside one 10 s window after the previous FULL.
      for (final id in _crowdIds) {
        trustWrites.controller.add((personId: id, amount: 0));
        await advance(const Duration(seconds: 1));
      }
      expect(badges(), isEmpty);
      // Nothing has been read yet, and the visible set is still the old one.
      expect(server.fullReads, before);
      expect(peerIds(), unorderedEquals(_crowdIds));

      await advance(const Duration(seconds: 40));

      expect(server.fullReads, before + 1);
      expect(
        gapBeforeLatestFull(),
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
      expect(peerIds(), isEmpty);
      expect(badges(), isEmpty);

      // And no second spaced FULL follows the coalesced one.
      await advance(const Duration(seconds: 40));
      expect(server.fullReads, before + 1);
    });

    test('a removal learned from relationship hints joins the same spaced '
        'FULL as an own write', () async {
      server.field = _crowdField();
      await store.requestRefresh(ConstellationRefreshReason.load);
      await settle();
      await advance(const Duration(seconds: 3));
      final before = server.fullReads;
      server.field = _crowdField(withdrawn: {'p1', 'p2'});
      reads.relations = [
        const ConstellationViewerRelation(
          personId: 'p2',
          viewerTrusts: false,
          trustsViewer: false,
        ),
      ];

      trustWrites.controller.add((personId: 'p1', amount: 0));
      await advance(const Duration(seconds: 2));
      hint(RealtimeEntityKind.relationship, 'p2', actor: 'p2');
      await advance(const Duration(seconds: 40));

      expect(server.fullReads, before + 1);
      expect(
        gapBeforeLatestFull(),
        greaterThanOrEqualTo(const Duration(seconds: 10)),
      );
      expect(peerIds(), ['p3', 'p4', 'p5']);
    });
  });

  group('an added trust edge', () {
    test('the ring turns at once and no FULL is dispatched', () async {
      trustWrites.controller.add((personId: 'omar', amount: 1));
      await settle();
      expect(badges()['omar'], ConstellationTrustBadge.mutual);

      await advance(const Duration(seconds: 30));

      expect(server.fullReads, 1);
    });

    test('a relationship hint showing new trust patches the ring and '
        'dispatches no FULL', () async {
      reads.relations = [
        const ConstellationViewerRelation(
          personId: 'omar',
          viewerTrusts: true,
          trustsViewer: true,
        ),
      ];

      hint(RealtimeEntityKind.relationship, 'omar', actor: 'omar');
      await advance(const Duration(seconds: 30));

      expect(badges()['omar'], ConstellationTrustBadge.mutual);
      expect(server.fullReads, 1);
    });
  });
}
