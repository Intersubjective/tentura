@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/beacon_access_policy.dart';

import '../../support/beacon_hierarchy_fixture.dart';
import '../../support/pg_test_public_keys.dart';

/// One beacon per status. Drafts are unpublished and relationship-free, as in
/// production (room, steward, forward and offer rows need a published
/// request); every other status is published with the same relationships.
String _beaconId(BeaconStatus status) => 'Baclp${status.smallintValue}';

const _author = 'Uaclpauthor';
const _steward = 'Uaclpsteward';
const _admitted = 'Uaclpadmitted';
const _fwdRecipient = 'Uaclpfwdrecv';
const _fwdSender = 'Uaclpfwdsend';
const _offerer = 'Uaclpofferer';
const _withdrawn = 'Uaclpwithdrawn';
const _trusted = 'Uaclptrusted';
const _stranger = 'Uaclpstranger';
const _blocked = 'Uaclpblocked';
const _ctxParent = 'Uaclpctxpar';
const _ctxChild = 'Uaclpctxchild';
const _ctxBoth = 'Uaclpctxboth';

/// Hierarchy context family per status: root R (open) → M (the status under
/// test) → leaf K (open). Context viewers are admitted to R and/or K.
String _ctxRoot(BeaconStatus s) => 'Bactxr${s.smallintValue}';
String _ctxMiddle(BeaconStatus s) => 'Bactxm${s.smallintValue}';
String _ctxLeaf(BeaconStatus s) => 'Bactxk${s.smallintValue}';

/// Context viewer → (admitted to R, admitted to K, blocked by the owner).
const _ctxViewers = <String, (bool, bool, bool)>{
  _ctxParent: (true, false, false),
  _ctxChild: (false, true, false),
  _ctxBoth: (true, true, false),
  _stranger: (false, false, false),
  _blocked: (false, true, true),
};

/// Known relationship facts per persona on every non-draft seeded beacon.
typedef _Persona = ({
  String id,
  bool isBlocked,
  bool isAuthor,
  bool isSteward,
  bool isAdmitted,
  bool isForwardRecipient,
  bool isActiveOfferer,
  bool isTrustVisible,
});

_Persona _persona(
  String id, {
  bool isBlocked = false,
  bool isAuthor = false,
  bool isSteward = false,
  bool isAdmitted = false,
  bool isForwardRecipient = false,
  bool isActiveOfferer = false,
  bool isTrustVisible = false,
}) => (
  id: id,
  isBlocked: isBlocked,
  isAuthor: isAuthor,
  isSteward: isSteward,
  isAdmitted: isAdmitted,
  isForwardRecipient: isForwardRecipient,
  isActiveOfferer: isActiveOfferer,
  isTrustVisible: isTrustVisible,
);

final _personas = <_Persona>[
  _persona(_author, isAuthor: true),
  _persona(_steward, isSteward: true),
  _persona(_admitted, isAdmitted: true),
  _persona(_fwdRecipient, isForwardRecipient: true),
  _persona(_fwdSender),
  _persona(_offerer, isActiveOfferer: true),
  _persona(_withdrawn),
  _persona(_trusted, isTrustVisible: true),
  _persona(_stranger),
  // Admitted in the room, but blocked by the owner.
  _persona(_blocked, isBlocked: true),
];

Future<void> main() async {
  final reachable = await canConnectBeaconHierarchyPostgres();
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon access level PG test';

  group('beacon access level SQL parity — disposable Postgres', () {
    late BeaconHierarchyDisposablePgTarget target;
    late Connection writer;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
      await target.recreate();
      final session = await openBeaconHierarchyPgSession(target);
      writer = session.writer;
      await session.db.close();
      await _seed(writer);
      await _seedContext(writer);
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await writer.close();
      await target.drop();
    });

    Future<Object?> scalar(
      String fn,
      String viewerId, [
      BeaconStatus status = BeaconStatus.open,
    ]) async {
      final rows = await writer.execute(
        Sql.named('SELECT public.$fn(@b, @v)'),
        parameters: {'b': _beaconId(status), 'v': viewerId},
      );
      return rows.first.first;
    }

    Future<void> setPublishedAt(BeaconStatus status, String? at) =>
        writer.execute(
          Sql.named(
            'UPDATE public.beacon SET published_at = @at::timestamptz '
            'WHERE id = @b',
          ),
          parameters: {'b': _beaconId(status), 'at': at},
        );

    Future<bool> isMember(
      String userId, [
      BeaconStatus status = BeaconStatus.open,
    ]) async {
      final rows = await writer.execute(
        Sql.named(
          'SELECT EXISTS (SELECT 1 FROM public.beacon_member '
          'WHERE beacon_id = @b AND user_id = @u)',
        ),
        parameters: {'b': _beaconId(status), 'u': userId},
      );
      return rows.first.first! as bool;
    }

    test(
      'reasons/level match BeaconAccessPolicy and existing predicates '
      'for every persona and status',
      () async {
        for (final status in BeaconStatus.values) {
          for (final p in _personas) {
            final label = '${p.id} @ ${status.name}';
            final related = status != BeaconStatus.draft;
            final facts = BeaconAccessFacts(
              status: status,
              isBlocked: p.isBlocked,
              isAuthor: p.isAuthor,
              isSteward: related && p.isSteward,
              isAdmitted: related && p.isAdmitted,
              hasActiveForwardEdgeAsRecipient: related && p.isForwardRecipient,
              isActiveHelpOfferer: related && p.isActiveOfferer,
              isDiscoverable: true,
              isPublished: related,
              isTrustVisibleWithAuthor: p.isTrustVisible,
              isMemberOfImmediateParent: false,
              isMemberOfDescendant: false,
            );
            final reasons = await scalar('beacon_access_reasons', p.id, status);
            final level =
                (await scalar('beacon_access_level', p.id, status))! as int;
            final canRead = await scalar(
              'beacon_can_read_content',
              p.id,
              status,
            );

            expect(reasons, BeaconAccessPolicy.reasons(facts), reason: label);
            expect(level, BeaconAccessPolicy.level(facts).value, reason: label);
            expect(level <= 2, canRead, reason: 'content $label');
            if (status != BeaconStatus.deleted) {
              final admission = await scalar(
                'beacon_effective_admission',
                p.id,
                status,
              );
              expect(level <= 1, admission, reason: 'admission $label');
            }
          }
        }
      },
      skip: skipReason,
    );

    test(
      'hierarchy context reasons/level match BeaconAccessPolicy '
      'for every middle status',
      () async {
        Future<Object?> at(String fn, String beaconId, String viewerId) async {
          final rows = await writer.execute(
            Sql.named('SELECT public.$fn(@b, @v)'),
            parameters: {'b': beaconId, 'v': viewerId},
          );
          return rows.first.first;
        }

        var contextBitsSeen = 0;
        for (final status in BeaconStatus.values) {
          final middlePublished = status != BeaconStatus.draft;
          for (final MapEntry(key: viewer, value: (inRoot, inLeaf, blocked))
              in _ctxViewers.entries) {
            // Members of R/K only count while the owner does not block them.
            final rootMember = inRoot && !blocked;
            final leafMember = inLeaf && !blocked;
            final cases = <(String, BeaconAccessFacts)>[
              (
                _ctxRoot(status),
                _ctxFacts(
                  status: BeaconStatus.open,
                  isBlocked: blocked,
                  isAdmitted: inRoot,
                  isPublished: true,
                  isMemberOfImmediateParent: false,
                  isMemberOfDescendant: leafMember,
                ),
              ),
              (
                _ctxMiddle(status),
                _ctxFacts(
                  status: status,
                  isBlocked: blocked,
                  isAdmitted: false,
                  isPublished: middlePublished,
                  isMemberOfImmediateParent: rootMember,
                  isMemberOfDescendant: leafMember,
                ),
              ),
              (
                _ctxLeaf(status),
                _ctxFacts(
                  status: BeaconStatus.open,
                  isBlocked: blocked,
                  isAdmitted: inLeaf,
                  isPublished: true,
                  isMemberOfImmediateParent: false,
                  isMemberOfDescendant: false,
                ),
              ),
            ];
            for (final (beaconId, facts) in cases) {
              final label = '$viewer @ $beaconId';
              final reasons =
                  (await at('beacon_access_reasons', beaconId, viewer))! as int;
              expect(reasons, BeaconAccessPolicy.reasons(facts), reason: label);
              expect(
                await at('beacon_access_level', beaconId, viewer),
                BeaconAccessPolicy.level(facts).value,
                reason: label,
              );
              expect(
                await at('beacon_can_read_content', beaconId, viewer),
                BeaconAccessPolicy.level(facts).canReadContent,
                reason: 'content $label',
              );
              contextBitsSeen |= reasons &
                  (BeaconAccessReason.contextChild.bit |
                      BeaconAccessReason.contextAncestor.bit);
            }
          }
        }
        expect(
          contextBitsSeen,
          BeaconAccessReason.contextChild.bit |
              BeaconAccessReason.contextAncestor.bit,
          reason: 'fixture must exercise both context bits',
        );
      },
      skip: skipReason,
    );

    test(
      'forward sender and withdrawn offerer get no reason bits',
      () async {
        expect(await scalar('beacon_access_reasons', _fwdSender), 0);
        expect(await scalar('beacon_access_reasons', _withdrawn), 0);
        expect(
          await scalar('beacon_access_reasons', _fwdRecipient),
          BeaconAccessReason.forwarded.bit,
        );
      },
      skip: skipReason,
    );

    test(
      'beacon_member includes eligible members and excludes draft, '
      'deleted and blocked rows',
      () async {
        expect(await isMember(_author), isTrue);
        expect(await isMember(_steward), isTrue);
        expect(await isMember(_admitted), isTrue);
        expect(await isMember(_blocked), isFalse, reason: 'blocked admitted');
        expect(await isMember(_stranger), isFalse);
        expect(await isMember(_offerer), isFalse);
        expect(await isMember(_trusted), isFalse);

        const draft = BeaconStatus.draft;
        const deleted = BeaconStatus.deleted;
        expect(await isMember(_author, draft), isFalse, reason: 'draft');
        // Excluded by status alone, even if a draft row carried published_at.
        await setPublishedAt(draft, '2026-01-01T00:00:00Z');
        try {
          expect(await isMember(_author, draft), isFalse);
        } finally {
          await setPublishedAt(draft, null);
        }
        expect(await isMember(_author, deleted), isFalse);
        expect(await isMember(_admitted, deleted), isFalse, reason: 'deleted');
        expect(await isMember(_steward, deleted), isFalse);
      },
      skip: skipReason,
    );
  });
}

Future<void> _seed(Connection writer) async {
  for (final (i, p) in _personas.indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
      // Namespace tag is two chars and slots are 1–9: roll over at 9 users.
      parameters: {
        'id': p.id,
        'key': pgTestPublicKey(i < 9 ? 'ac' : 'ad', i % 9 + 1),
      },
    );
  }
  for (final status in BeaconStatus.values) {
    final b = _beaconId(status);
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  @b, @author, 'Access level parity', '', @status, true,
  @publishedAt::timestamptz, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
      parameters: {
        'b': b,
        'author': _author,
        'status': status.smallintValue,
        'publishedAt': status == BeaconStatus.draft
            ? null
            : '2026-01-01T00:00:00Z',
      },
    );
    if (status == BeaconStatus.draft) {
      continue;
    }
    // Mirrors BeaconRoomRepository.setBeaconSteward: steward row plus a
    // participant row carrying the steward role.
    await writer.execute(
      Sql.named(
        'INSERT INTO public.beacon_steward (beacon_id, user_id) '
        'VALUES (@b, @u)',
      ),
      parameters: {'b': b, 'u': _steward},
    );
    for (final row in <(String, String, int, int)>[
      ('Paclpsteward', _steward, BeaconParticipantRoleBits.steward, 0),
      ('Paclpadmitted', _admitted, 0, RoomAccessBits.admitted),
      ('Paclpblocked', _blocked, 0, RoomAccessBits.admitted),
    ]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  @id, @b, @u, @role, 0, @access,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
        parameters: {
          'id': '${row.$1}${status.smallintValue}',
          'b': b,
          'u': row.$2,
          'role': row.$3,
          'access': row.$4,
        },
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (@id, @b, @sender, @recipient, now())
'''),
      parameters: {
        'id': 'Faclp${status.smallintValue}',
        'b': b,
        'sender': _fwdSender,
        'recipient': _fwdRecipient,
      },
    );
    for (final (userId, offerStatus) in [(_offerer, 0), (_withdrawn, 1)]) {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES (@b, @u, '', @s, now(), now())
'''),
        parameters: {'b': b, 'u': userId, 's': offerStatus},
      );
    }
  }
  await writer.execute(
    Sql.named('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES (@t, @a, 1, now(), now()), (@a, @t, 1, now(), now())
'''),
    parameters: {'t': _trusted, 'a': _author},
  );
  await writer.execute(
    Sql.named(
      'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
      'VALUES (@a, @v, @a)',
    ),
    parameters: {'a': _author, 'v': _blocked},
  );
}

BeaconAccessFacts _ctxFacts({
  required BeaconStatus status,
  required bool isBlocked,
  required bool isAdmitted,
  required bool isPublished,
  required bool isMemberOfImmediateParent,
  required bool isMemberOfDescendant,
}) => BeaconAccessFacts(
  status: status,
  isBlocked: isBlocked,
  isAuthor: false,
  isSteward: false,
  isAdmitted: isAdmitted,
  hasActiveForwardEdgeAsRecipient: false,
  isActiveHelpOfferer: false,
  isDiscoverable: true,
  isPublished: isPublished,
  isTrustVisibleWithAuthor: false,
  isMemberOfImmediateParent: isMemberOfImmediateParent,
  isMemberOfDescendant: isMemberOfDescendant,
);

Future<void> _seedContext(Connection writer) async {
  for (final (i, id) in [_ctxParent, _ctxChild, _ctxBoth].indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @key, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('cx', i + 1)},
    );
  }
  Future<void> insertBeacon(String id, String? parentId) => writer.execute(
    Sql.named('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable, parent_beacon_id,
  published_at, created_at, updated_at
) VALUES (
  @id, @author, 'Access context parity', '', 0, true, @parent,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
    parameters: {'id': id, 'author': _author, 'parent': parentId},
  );
  for (final status in BeaconStatus.values) {
    final root = _ctxRoot(status);
    final middle = _ctxMiddle(status);
    final leaf = _ctxLeaf(status);
    await insertBeacon(root, null);
    // Children need a published parent, so M gets its status after K exists.
    await insertBeacon(middle, root);
    await insertBeacon(leaf, middle);
    await writer.execute(
      Sql.named('''
UPDATE public.beacon
SET status = @status::smallint,
    published_at = CASE WHEN @status::smallint = 3 THEN NULL ELSE published_at END
WHERE id = @id
'''),
      parameters: {'id': middle, 'status': status.smallintValue},
    );
    for (final MapEntry(key: viewer, value: (inRoot, inLeaf, _))
        in _ctxViewers.entries) {
      for (final (beaconId, admitted) in [(root, inRoot), (leaf, inLeaf)]) {
        if (!admitted) {
          continue;
        }
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  @id, @b, @u, 0, 0, @access,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
          parameters: {
            'id': 'P$beaconId$viewer',
            'b': beaconId,
            'u': viewer,
            'access': RoomAccessBits.admitted,
          },
        );
      }
    }
  }
}
