import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';
import 'package:tentura/data/service/invalidation_service.dart';
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

import 'fake_clock_port.dart';
import 'fake_wake_up_port.dart';

const fieldViewerId = 'Uaaaaaaaaaaaa';
const fieldContactId = 'Ubbbbbbbbbbbb';
const fieldRequest = ConstellationRequest(
  id: 'Bnew',
  authorId: fieldContactId,
  title: 'Published without sending',
  status: 0,
);

ConstellationField fieldSnapshot({
  bool mutual = true,
  bool published = false,
}) => ConstellationField(
  loadedAt: DateTime.utc(2026, 10, 29),
  context: '',
  peers: const [ConstellationPerson(id: fieldContactId, displayName: 'Max')],
  directContactIds: const [fieldContactId],
  edges: [
    const ConstellationTrustEdgeEntity(
      src: fieldViewerId,
      dst: fieldContactId,
      tier: 1,
    ),
    if (mutual)
      const ConstellationTrustEdgeEntity(
        src: fieldContactId,
        dst: fieldViewerId,
        tier: 1,
      ),
  ],
  requests: published ? const [fieldRequest] : const [],
  anchorProjection: ConstellationAnchorProjection.empty,
);

final class RemoteFieldReads
    implements ConstellationRepositoryPort, ConstellationTargetedReadPort {
  ConstellationField field = fieldSnapshot();
  final relationReads = <Set<String>>[];
  final requestReads = <Set<String>>[];

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async => field;

  @override
  Future<List<ConstellationViewerRelation>> readViewerRelations(
    Set<String> personIds,
  ) async {
    relationReads.add(Set.of(personIds));
    return [
      if (personIds.contains(fieldContactId))
        ConstellationViewerRelation(
          personId: fieldContactId,
          viewerTrusts: true,
          trustsViewer: field.edges.any(
            (e) => e.src == fieldContactId && e.dst == fieldViewerId,
          ),
        ),
    ];
  }

  @override
  Future<List<ConstellationRequest>> fetchRequests(
    Set<String> beaconIds, {
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
  }) async {
    requestReads.add(Set.of(beaconIds));
    return [
      for (final r in field.requests)
        if (beaconIds.contains(r.id)) r,
    ];
  }
}

final class _Account implements ConstellationAccountPort {
  _Account(this.currentAccountChanges);
  @override
  final Stream<String> currentAccountChanges;
}

final class _Writes implements PersonTrustWritesPort {
  @override
  Stream<PersonTrustWrite> get personTrustWrites => const Stream.empty();
}

/// Real wire decoder, wire batch and Field freshness/store; only the socket,
/// clock and authorized reads are controlled by the test.
final class RemoteFieldFixture {
  RemoteFieldFixture(this.async) {
    invalidation = InvalidationService.forTesting(socket.stream);
    final sync = RealtimeSyncCase(invalidation);
    store = ConstellationFieldStoreCase(
      reads,
      _Account(account.stream),
      clock,
      wakeUp,
      sync,
      env: const Env(),
      logger: Logger('RemoteFieldTest'),
    );
    freshness = ConstellationFieldFreshnessCase(
      store,
      reads,
      _Writes(),
      sync,
      wakeUp,
      clock,
      env: const Env(),
      logger: Logger('RemoteFieldTest'),
    );
    async.flushMicrotasks();
    lease = store.lease();
    unawaited(store.requestRefresh(ConstellationRefreshReason.load));
    async.flushMicrotasks();
    expect(badge, ConstellationTrustBadge.mutual);
    advance(const Duration(seconds: 3));
  }

  final FakeAsync async;
  final socket = StreamController<Map<String, dynamic>>.broadcast();
  final account = BehaviorSubject<String>.seeded(fieldViewerId);
  final clock = FakeClockPort(DateTime.utc(2026, 10, 29));
  final wakeUp = FakeWakeUpPort();
  final reads = RemoteFieldReads();
  late final InvalidationService invalidation;
  late final ConstellationFieldStoreCase store;
  late final ConstellationFieldFreshnessCase freshness;
  late final StoreLease lease;

  ConstellationTrustBadge? get badge => constellationTrustBadges(
    field: store.current.field!,
    viewerId: fieldViewerId,
  )[fieldContactId];

  void hint(String kind, String id, {String? actor, String event = 'update'}) {
    socket.add({
      'type': 'subscription',
      'path': 'entity_changes',
      'payload': {
        'entity': kind,
        'id': id,
        'event': event,
        'actor_user_id': ?actor,
      },
    });
    async.flushMicrotasks();
  }

  void advance(Duration duration) {
    const step = Duration(milliseconds: 50);
    for (var elapsed = Duration.zero; elapsed < duration; elapsed += step) {
      clock.advance(step);
      async.elapse(step);
      wakeUp.elapse(step);
      async.flushMicrotasks();
    }
  }

  void dispose() {
    unawaited(freshness.dispose());
    lease.dispose();
    unawaited(store.dispose());
    unawaited(invalidation.dispose());
    unawaited(account.close());
    unawaited(socket.close());
    async.flushMicrotasks();
  }
}
