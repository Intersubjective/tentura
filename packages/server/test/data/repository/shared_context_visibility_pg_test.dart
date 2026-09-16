@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/domain/beacon_lineage_visibility.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/pg_test_public_keys.dart';
import 'beacon_hierarchy_pg_helpers.dart';
import 'beacon_hierarchy_visibility_pg_support.dart';

// Own topology (issue #146 T09): owners dave/eve are never matrix viewers, so
// alice/bob/carol are plain admitted members and frank is a true stranger.
const _a = BeaconHierarchyTopology.beaconA; // owner dave, root
const _b = BeaconHierarchyTopology.beaconB; // owner eve, child of A
const _c = BeaconHierarchyTopology.beaconC; // owner dave, child of B
const _d = BeaconHierarchyTopology.beaconD; // owner eve, child of A
const _beacons = [_a, _b, _c, _d];

const _alice = BeaconHierarchyTopology.aliceId; // member of A
const _bob = BeaconHierarchyTopology.bobId; // member of B
const _carol = BeaconHierarchyTopology.carolId; // member of C
const _dave = BeaconHierarchyTopology.daveId;
const _eve = BeaconHierarchyTopology.eveId;
const _frank = BeaconHierarchyTopology.frankId; // stranger

const _admitted = BeaconAccessReason.admitted;
const _child = BeaconAccessReason.contextChild;
const _ancestor = BeaconAccessReason.contextAncestor;

/// Expected `beacon_access_reasons` per viewer for A, B, C, D.
final _matrix = <String, List<int>>{
  _alice: [_admitted.bit, _child.bit, 0, _child.bit],
  _bob: [_ancestor.bit, _admitted.bit, _child.bit, 0],
  _carol: [_ancestor.bit, _ancestor.bit, _admitted.bit, 0],
  _frank: [0, 0, 0, 0],
};

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for shared context PG test';

  group('shared context visibility — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;
    late BeaconHierarchyFixture fixture;
    late BeaconAccessRepository access;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      fixture = BeaconHierarchyFixture(writer: writer, db: session.db);
      access = BeaconAccessRepository(session.db);
    });

    Future<void> admit(String id, String beaconId, String userId) =>
        writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  @id, @beaconId, @userId, 0, 0, @roomAccess,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
          parameters: {
            'id': id,
            'beaconId': beaconId,
            'userId': userId,
            'roomAccess': RoomAccessBits.admitted,
          },
        );

    Future<void> leave(String participantId) => writer.execute(
      Sql.named(
        'UPDATE public.beacon_participant SET room_access = @left WHERE id = @id',
      ),
      parameters: {'left': RoomAccessBits.left, 'id': participantId},
    );

    setUp(() async {
      if (skipReason != false) {
        return;
      }
      for (final (i, id) in BeaconHierarchyTopology.allUserIds.indexed) {
        await writer.execute(
          Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
          parameters: {'id': id, 'publicKey': pgTestPublicKey('bctx', i + 1)},
        );
      }
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, published_at, created_at, updated_at
) VALUES (
  @id, @ownerId, 'Request A', '', 0,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
        parameters: {'id': _a, 'ownerId': _dave},
      );
      for (final (id, parent, owner) in [
        (_b, _a, _eve),
        (_c, _b, _dave),
        (_d, _a, _eve),
      ]) {
        await insertPublishedChildBeacon(
          writer: writer,
          childId: id,
          parentId: parent,
          ownerId: owner,
          title: 'Request $id',
        );
      }
      await admit('PhieraliceA01', _a, _alice);
      await admit('PhierbobB01', _b, _bob);
      await admit('PhiercarolC01', _c, _carol);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.user_block WHERE blocker_id LIKE 'Uhier%' "
        "OR blocked_id LIKE 'Uhier%'",
      );
      await fixture.tearDown();
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await fixture.db.close();
      await writer.close();
      await target.drop();
    });

    Future<int> reasons(String beaconId, String viewerId) async {
      final row = await writer.execute(
        Sql.named('SELECT public.beacon_access_reasons(@b, @v)'),
        parameters: {'b': beaconId, 'v': viewerId},
      );
      return row.first.first! as int;
    }

    Future<int> level(String beaconId, String viewerId) async {
      final row = await writer.execute(
        Sql.named('SELECT public.beacon_access_level(@b, @v)'),
        parameters: {'b': beaconId, 'v': viewerId},
      );
      return row.first.first! as int;
    }

    Future<bool> canRead(String beaconId, String viewerId) =>
        access.canReadContent(beaconId: beaconId, viewerId: viewerId);

    Future<void> expectNoAccess(String viewerId, List<String> beaconIds) async {
      for (final beaconId in beaconIds) {
        expect(await canRead(beaconId, viewerId), isFalse,
            reason: '$viewerId content on $beaconId');
        expect(await reasons(beaconId, viewerId), 0,
            reason: '$viewerId reasons on $beaconId');
      }
    }

    test('context matrix for A→B→C, A→D', () async {
      for (final MapEntry(key: viewer, value: expected) in _matrix.entries) {
        for (final (i, beaconId) in _beacons.indexed) {
          final label = '$viewer on $beaconId';
          expect(await reasons(beaconId, viewer), expected[i], reason: label);
          expect(
            await canRead(beaconId, viewer),
            expected[i] != 0,
            reason: label,
          );
          final bits = expected[i] & (_child.bit | _ancestor.bit);
          if (bits != 0) {
            expect(
              await level(beaconId, viewer),
              BeaconAccessLevel.observer.value,
              reason: label,
            );
          }
        }
      }
    }, skip: skipReason);

    test('S4-10: leaving B removes every grant bob had through it', () async {
      await leave('PhierbobB01');
      await expectNoAccess(_bob, _beacons);
    }, skip: skipReason);

    test('block by B owner removes bob context on A and C', () async {
      expect(await canRead(_a, _bob), isTrue);
      expect(await canRead(_c, _bob), isTrue);
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@blocker, @blocked, @blocked)
'''),
        parameters: {'blocker': _eve, 'blocked': _bob},
      );
      await expectNoAccess(_bob, _beacons);
    }, skip: skipReason);

    test('deleted B grants no context and is unreadable', () async {
      await writer.execute(
        Sql.named('UPDATE public.beacon SET status = 2 WHERE id = @id'),
        parameters: {'id': _b},
      );
      await expectNoAccess(_carol, [_b]);
      expect(await reasons(_a, _carol), _ancestor.bit,
          reason: 'carol still reaches A through C');
      await expectNoAccess(_bob, _beacons);
    }, skip: skipReason);

    test('a draft child never grants context to its author', () async {
      const draftId = 'BhierDraftF1';
      await admit('PhierfrankA01', _a, _frank);
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, parent_beacon_id,
  created_at, updated_at
) VALUES (
  @id, @ownerId, 'Draft child of A', '', 3, @parentId,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
        parameters: {'id': draftId, 'ownerId': _frank, 'parentId': _a},
      );
      expect(await reasons(_a, _frank), _admitted.bit);
      expect(await reasons(draftId, _frank), BeaconAccessReason.author.bit);

      await leave('PhierfrankA01');
      await expectNoAccess(_frank, _beacons);
    }, skip: skipReason);

    test('S4-14: B member is not an observer of sibling D', () async {
      await expectNoAccess(_bob, [_d]);
    }, skip: skipReason);

    group('D2: context observer acts as an ordinary observer', () {
      late HierarchyOnlyViewerHarness harness;

      setUp(() {
        harness = HierarchyOnlyViewerHarness(
          access: access,
          childBeaconId: _b,
          hierarchyOnlyViewerId: _alice,
        );
      });

      test('offers and withdraws help on open child B', () async {
        final case_ = harness.buildHelpOfferCase(lockedBeaconAuthorId: _eve);
        await case_.offerHelp(beaconId: _b, userId: _alice);
        await case_.withdraw(
          beaconId: _b,
          userId: _alice,
          withdrawReason: 'other',
        );
      });

      test('forwards child B; recipient becomes forwarded only', () async {
        final case_ = harness.buildForwardCase(
          authorId: _eve,
          onEdgesCreated: (recipientIds) async {
            for (final recipientId in recipientIds) {
              await writer.execute(
                Sql.named(r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'FhierctxB01', @beaconId, @senderId, @recipientId, '2026-01-02T00:00:00Z'
)
'''),
                parameters: {
                  'beaconId': _b,
                  'senderId': _alice,
                  'recipientId': recipientId,
                },
              );
            }
          },
        );
        final result = await case_.forward(
          beaconId: _b,
          senderId: _alice,
          recipientIds: [_frank],
        );
        expect(result.deliveredRecipientIds, [_frank]);
        expect(await reasons(_b, _frank), BeaconAccessReason.forwarded.bit);
        await expectNoAccess(_frank, [_a, _c, _d]);
      });

      test('lineage source and invitation accept the context observer',
          () async {
        await assertBeaconLineageSourceVisible(
          guard: access,
          beaconId: _b,
          userId: _alice,
        );
        final invitation = await harness
            .buildInvitationCase(authorId: _eve)
            .create(userId: _alice, addresseeName: 'target', beaconId: _b);
        expect(invitation.beaconId, _b);
      });
    }, skip: skipReason);
  });
}
