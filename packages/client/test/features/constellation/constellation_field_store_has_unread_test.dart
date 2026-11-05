import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_read_cursor.dart';
import 'package:tentura/domain/entity/realtime/realtime_room_message_paint.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_account_port.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_store_case.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../../support/fake_clock_port.dart';
import '../../support/fake_wake_up_port.dart';
import '../../support/test_realtime_sync.dart';

ConstellationAnchorRevision _revision(int value) =>
    ConstellationAnchorRevision(BigInt.from(value));

ConstellationField _fieldWithPost({
  required String postId,
  bool hasUnread = false,
}) => ConstellationField(
  loadedAt: DateTime.utc(2026, 11, 4),
  context: '',
  posts: [
    ConstellationPost(
      id: postId,
      authorId: 'author',
      rootExcerpt: 'hello',
      lastActivityAt: DateTime.utc(2026, 11, 4),
      hasUnread: hasUnread,
    ),
  ],
  anchorProjection: ConstellationAnchorProjection(
    revision: _revision(1),
    anchors: const [],
    pinnedPeers: const [],
    pinnedRequests: const [],
    supportPeers: const [],
    supportEdges: const [],
    serverFilteredBeaconIds: const [],
    serverFilteredBeaconCount: 0,
  ),
);

RealtimeEntityChange _message({
  required String beaconId,
  required String authorId,
  int? systemMessageKind,
}) => RealtimeEntityChange(
  kind: RealtimeEntityKind.roomMessage,
  aggregateId: beaconId,
  operation: RealtimeOperation.insert,
  source: RealtimeChangeSource.serverInvalidation,
  actorUserId: authorId,
  roomMessagePaint: RealtimeRoomMessagePaint(
    id: 'm1',
    beaconId: beaconId,
    authorId: authorId,
    body: 'hi',
    createdAt: DateTime.utc(2026, 11, 4),
    systemMessageKind: systemMessageKind,
  ),
);

void main() {
  group('ConstellationFieldStoreCase hasUnread (#256)', () {
    test('FULL mapping leaves hasUnread from the repository payload', () async {
      final account = BehaviorSubject<String>.seeded('viewer');
      addTearDown(account.close);
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final repo = _FetchOnceRepository(
        _fieldWithPost(postId: 'p1', hasUnread: true),
      );
      final store = ConstellationFieldStoreCase(
        repo,
        _AccountPort(account.stream),
        FakeClockPort(DateTime.utc(2026, 11, 4)),
        FakeWakeUpPort(),
        realtime.case_,
        env: const Env.fromEnvironment(),
        logger: Logger('test'),
      )..lease();
      await Future<void>.delayed(Duration.zero);
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(store.current.field?.posts.single.hasUnread, isTrue);
    });

    test(
      'roomMessage from another user marks unread without a Field refetch',
      () async {
        final account = BehaviorSubject<String>.seeded('viewer');
        addTearDown(account.close);
        final port = TestRealtimeSyncPort(synchronousChanges: true);
      final realtime = (case_: RealtimeSyncCase(port), port: port);
        addTearDown(realtime.port.dispose);
        final repo = _FetchOnceRepository(_fieldWithPost(postId: 'p1'));
        final store = ConstellationFieldStoreCase(
          repo,
          _AccountPort(account.stream),
          FakeClockPort(DateTime.utc(2026, 11, 4)),
          FakeWakeUpPort(),
          realtime.case_,
          env: const Env.fromEnvironment(),
          logger: Logger('test'),
        )..lease();
        await Future<void>.delayed(Duration.zero);
        unawaited(store.requestRefresh(ConstellationRefreshReason.load));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(repo.fetchCount, 1);

        realtime.port.emitChange(_message(beaconId: 'p1', authorId: 'other'));
        await Future<void>.delayed(Duration.zero);

        expect(store.current.field?.posts.single.hasUnread, isTrue);
        expect(repo.fetchCount, 1);
      },
    );

    test('system roomMessage does not mark unread', () async {
      final account = BehaviorSubject<String>.seeded('viewer');
      addTearDown(account.close);
      final port = TestRealtimeSyncPort(synchronousChanges: true);
      final realtime = (case_: RealtimeSyncCase(port), port: port);
      addTearDown(realtime.port.dispose);
      final repo = _FetchOnceRepository(_fieldWithPost(postId: 'p1'));
      final store = ConstellationFieldStoreCase(
        repo,
        _AccountPort(account.stream),
        FakeClockPort(DateTime.utc(2026, 11, 4)),
        FakeWakeUpPort(),
        realtime.case_,
        env: const Env.fromEnvironment(),
        logger: Logger('test'),
      )..lease();
      await Future<void>.delayed(Duration.zero);
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      realtime.port.emitChange(
        _message(beaconId: 'p1', authorId: 'other', systemMessageKind: 5),
      );
      await Future<void>.delayed(Duration.zero);

      expect(store.current.field?.posts.single.hasUnread, isFalse);
      expect(repo.fetchCount, 1);
    });

    test('viewer roomSeen clears unread without refetch', () async {
      final account = BehaviorSubject<String>.seeded('viewer');
      addTearDown(account.close);
      final port = TestRealtimeSyncPort(synchronousChanges: true);
      final realtime = (case_: RealtimeSyncCase(port), port: port);
      addTearDown(realtime.port.dispose);
      final repo = _FetchOnceRepository(
        _fieldWithPost(postId: 'p1', hasUnread: true),
      );
      final store = ConstellationFieldStoreCase(
        repo,
        _AccountPort(account.stream),
        FakeClockPort(DateTime.utc(2026, 11, 4)),
        FakeWakeUpPort(),
        realtime.case_,
        env: const Env.fromEnvironment(),
        logger: Logger('test'),
      )..lease();
      await Future<void>.delayed(Duration.zero);
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      realtime.port.emitChange(
        RealtimeEntityChange(
          kind: RealtimeEntityKind.roomSeen,
          aggregateId: 'p1',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
          readCursor: RealtimeReadCursor(
            threadItemId: null,
            lastSeenAt: DateTime.utc(2026, 11, 4, 1),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(store.current.field?.posts.single.hasUnread, isFalse);
      expect(repo.fetchCount, 1);
    });

    test('roomMessage for a beacon not on the Field is unchanged', () async {
      final account = BehaviorSubject<String>.seeded('viewer');
      addTearDown(account.close);
      final port = TestRealtimeSyncPort(synchronousChanges: true);
      final realtime = (case_: RealtimeSyncCase(port), port: port);
      addTearDown(realtime.port.dispose);
      final repo = _FetchOnceRepository(_fieldWithPost(postId: 'p1'));
      final store = ConstellationFieldStoreCase(
        repo,
        _AccountPort(account.stream),
        FakeClockPort(DateTime.utc(2026, 11, 4)),
        FakeWakeUpPort(),
        realtime.case_,
        env: const Env.fromEnvironment(),
        logger: Logger('test'),
      )..lease();
      await Future<void>.delayed(Duration.zero);
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final before = store.current.field;

      realtime.port.emitChange(
        _message(beaconId: 'elsewhere', authorId: 'other'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(identical(store.current.field, before), isTrue);
      expect(repo.fetchCount, 1);
    });

    test('opening from the Field clears unread optimistically', () async {
      final account = BehaviorSubject<String>.seeded('viewer');
      addTearDown(account.close);
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final repo = _FetchOnceRepository(
        _fieldWithPost(postId: 'p1', hasUnread: true),
      );
      final store = ConstellationFieldStoreCase(
        repo,
        _AccountPort(account.stream),
        FakeClockPort(DateTime.utc(2026, 11, 4)),
        FakeWakeUpPort(),
        realtime.case_,
        env: const Env.fromEnvironment(),
        logger: Logger('test'),
      )..lease();
      await Future<void>.delayed(Duration.zero);
      unawaited(store.requestRefresh(ConstellationRefreshReason.load));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      store.applyOpenedFieldBeacon('p1');

      expect(store.current.field?.posts.single.hasUnread, isFalse);
    });
  });
}

final class _FetchOnceRepository implements ConstellationRepositoryPort {
  _FetchOnceRepository(this.field);

  final ConstellationField field;
  int fetchCount = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetchCount++;
    return field;
  }
}

final class _AccountPort implements ConstellationAccountPort {
  _AccountPort(this.currentAccountChanges);

  @override
  final Stream<String> currentAccountChanges;
}
