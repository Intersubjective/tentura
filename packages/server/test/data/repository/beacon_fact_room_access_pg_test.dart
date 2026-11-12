@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// `BeaconFactCardRepository.loadRoomAccess` reads the one fact access rule
/// (`public.beacon_fact_access`): a blocked participant, a deleted beacon and
/// a draft are all closed to fact reads and writes, and the result carries
/// the beacon `kind`, `isDraft` and `isExpiredPost`.

const _author = 'Uroomacauth0';
const _steward = 'Uroomacsteww';
const _member = 'Uroomacmembr';
const _leaver = 'Uroomacleavr';
const _stranger = 'Uroomacstrng';
const _blockedMember = 'Uroomacblkmb';

const _openRequest = 'Broomacopenrq';
const _draftRequest = 'Broomacdraftr';
const _deletedRequest = 'Broomacdelete';
const _openPost = 'Broomacopenps';
const _openPostRoot = 'Rroomacopenps';
const _rootlessOpenPost = 'Broomacnoroot';
const _expiredOpenPost = 'Broomacexpird';
const _unknown = 'Broomacmissng';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_ROOM_ACCESS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_room_access',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late BeaconFactCardRepository repository;

  /// The Dart result must be the same row the SQL access rule gives for the
  /// same beacon and user (no hard-coded copy of the rule in Dart).
  Future<BeaconFactRoomAccess> loadAndCompare(
    String beaconId,
    String userId,
  ) async {
    final access = await repository.loadRoomAccess(
      beaconId: beaconId,
      userId: userId,
    );
    final result = await session.writer.execute(
      Sql.named('''
SELECT beacon_exists, kind, status, is_draft, is_expired_post, can_read,
       can_use_room
FROM public.beacon_fact_access(@beacon, @user)
'''),
      parameters: {'beacon': beaconId, 'user': userId},
    );
    expect(result, hasLength(1));
    final row = result.single.toColumnMap();
    expect(access.exists, row['beacon_exists'], reason: 'exists');
    expect(access.canUseRoom, row['can_use_room'], reason: 'canUseRoom');
    expect(access.canReadContent, row['can_read'], reason: 'canReadContent');
    if (row['beacon_exists'] == true) {
      expect(access.beaconStatus, row['status'], reason: 'beaconStatus');
      expect(access.kind, row['kind'], reason: 'kind');
      expect(access.isDraft, row['is_draft'], reason: 'isDraft');
      expect(
        access.isExpiredPost,
        row['is_expired_post'],
        reason: 'isExpiredPost',
      );
    }
    return access;
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    await _seed(session.writer);
    db = TenturaDb.forTest(
      database: PgDatabase.opened(
        Pool<dynamic>.withEndpoints(
          [target.databaseEnv.pgEndpoint],
          settings: target.databaseEnv.pgPoolSettings,
        ),
        enableMigrations: false,
      ),
    );
    repository = BeaconFactCardRepository(db, BeaconRoomRepository(db));
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  group('loadRoomAccess on an open Request', () {
    for (final (label, userId) in [
      ('author', _author),
      ('steward', _steward),
      ('admitted participant', _member),
    ]) {
      test(
        'the $label may use the room and read, with Request facts',
        () async {
          final access = await loadAndCompare(_openRequest, userId);
          expect(access.exists, isTrue);
          expect(access.beaconStatus, 0);
          expect(access.kind, 0);
          expect(access.isDraft, isFalse);
          expect(access.isExpiredPost, isFalse);
          expect(access.canUseRoom, isTrue);
          expect(access.canReadContent, isTrue);
        },
      );
    }

    test('a leaver reads but may not use the room', () async {
      final access = await loadAndCompare(_openRequest, _leaver);
      expect(access.canReadContent, isTrue);
      expect(access.canUseRoom, isFalse);
    });

    test('a stranger neither reads nor uses the room', () async {
      final access = await loadAndCompare(_openRequest, _stranger);
      expect(access.exists, isTrue);
      expect(access.canReadContent, isFalse);
      expect(access.canUseRoom, isFalse);
    });

    test('an admitted participant in a block pair with the author is shut '
        'out of reading and of the room', () async {
      final access = await loadAndCompare(_openRequest, _blockedMember);
      expect(access.canReadContent, isFalse);
      expect(access.canUseRoom, isFalse);
    });
  });

  group('loadRoomAccess on unknown, deleted and draft beacons', () {
    test('an unknown beacon id reports no access and does not throw', () async {
      final access = await loadAndCompare(_unknown, _author);
      expect(access.exists, isFalse);
      expect(access.canUseRoom, isFalse);
      expect(access.canReadContent, isFalse);
    });

    test('the author of a deleted beacon may not use the room', () async {
      final access = await loadAndCompare(_deletedRequest, _author);
      expect(access.exists, isTrue);
      expect(access.beaconStatus, 2);
      expect(access.canUseRoom, isFalse);
      expect(access.canReadContent, isFalse);
    });

    test('a draft Request is a draft for every caller and usable by its '
        'author only', () async {
      final author = await loadAndCompare(_draftRequest, _author);
      expect(author.isDraft, isTrue);
      expect(author.canUseRoom, isTrue);
      expect(author.canReadContent, isTrue);
      final other = await loadAndCompare(_draftRequest, _member);
      expect(other.isDraft, isTrue);
      expect(other.canUseRoom, isFalse);
      expect(other.canReadContent, isFalse);
    });
  });

  group('loadRoomAccess on Posts', () {
    test('an open Post without a root message is a draft Post', () async {
      final access = await loadAndCompare(_rootlessOpenPost, _author);
      expect(access.kind, 1);
      expect(access.isDraft, isTrue);
      expect(access.isExpiredPost, isFalse);
    });

    test('an open Post with a root message is not a draft', () async {
      final access = await loadAndCompare(_openPost, _author);
      expect(access.kind, 1);
      expect(access.isDraft, isFalse);
      expect(access.isExpiredPost, isFalse);
    });

    test('an open Post past its expiry is an expired Post', () async {
      final access = await loadAndCompare(_expiredOpenPost, _author);
      expect(access.kind, 1);
      expect(access.isExpiredPost, isTrue);
    });
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('TRUNCATE public."user" CASCADE');
  const users = [
    _author,
    _steward,
    _member,
    _leaver,
    _stranger,
    _blockedMember,
  ];
  for (final (index, id) in users.indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': id, 'key': pgTestPublicKey('froomacc', index + 1)},
    );
  }

  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind, published_at)
VALUES ('$_openRequest', '$_author', 'Open', '', 0, 0, now()),
       ('$_deletedRequest', '$_author', 'Deleted', '', 0, 0, now()),
       ('$_draftRequest', '$_author', 'Draft', '', 3, 0, NULL)
''');
  await writer.execute(
    "UPDATE public.beacon SET status = 2 WHERE id = '$_deletedRequest'",
  );

  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES ('$_openPost', '$_author', '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours'),
       ('$_rootlessOpenPost', '$_author', '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours'),
       ('$_expiredOpenPost', '$_author', '', '', 0, 1, 1, false,
        now() - interval '73 hours', now() - interval '1 hour')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_openPostRoot', '$_openPost', '$_author', 'Root')
''');
  await writer.execute('''
UPDATE public.beacon SET post_root_message_id = '$_openPostRoot'
WHERE id = '$_openPost'
''');

  await writer.execute('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES ('$_openRequest', '$_steward')
''');

  final participants = <(String, String, int)>[
    (_openRequest, _member, 3),
    (_openRequest, _leaver, 5),
    (_openRequest, _blockedMember, 3),
    (_draftRequest, _member, 3),
  ];
  for (final (index, (beaconId, userId, roomAccess)) in participants.indexed) {
    await writer.execute('''
INSERT INTO public.beacon_participant (id, beacon_id, user_id, role, status, room_access)
VALUES ('Proomac$index', '$beaconId', '$userId', 0, 0, $roomAccess)
''');
  }

  // A forward edge keeps the leaver able to read the content.
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Froomac0', '$_openRequest', '$_author', '$_leaver')
''');

  await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_author', '$_blockedMember', '$_blockedMember')
''');
}
