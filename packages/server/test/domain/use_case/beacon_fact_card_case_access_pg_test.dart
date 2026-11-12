@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// `BeaconFactCardCase` over the real repository and a real Postgres: a
/// participant who was admitted to a Request but is in a block pair with its
/// author, and the author of a deleted beacon, are refused fact reads, fact
/// history and fact edits with `UnauthorizedException`.

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

// Real, live facts: only the access rule decides the outcome of a call.
const _openRequestFact = 'Ffroomacopen';
const _deletedRequestFact = 'Ffroomacdele';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_FACT_CARD_CASE_ACCESS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_fact_case_access',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb db;
  late BeaconFactCardCase useCase;

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
    final room = BeaconRoomRepository(db);
    useCase = BeaconFactCardCase(
      BeaconFactCardRepository(db, room),
      room,
      _UnusedImage(),
      _UnusedTasks(),
      BeaconHierarchyRepository(db),
      BeaconAccessRepository(db),
      env: Env(environment: Environment.test),
      logger: Logger('BeaconFactCardCaseAccessPgTest'),
    );
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  group(
    'BeaconFactCardCase refuses callers the fact access rule shuts out',
    () {
      test(
        'history refuses an admitted participant blocked by the author',
        () async {
          await expectLater(
            useCase.history(
              factCardId: _openRequestFact,
              beaconId: _openRequest,
              userId: _blockedMember,
            ),
            throwsA(isA<UnauthorizedException>()),
          );
        },
      );

      test(
        'correct refuses an admitted participant blocked by the author',
        () async {
          await expectLater(
            useCase.correct(
              factCardId: _openRequestFact,
              beaconId: _openRequest,
              actorUserId: _blockedMember,
              newText: 'edited',
              baseRevisionSeq: 1,
            ),
            throwsA(isA<UnauthorizedException>()),
          );
        },
      );

      test(
        'list refuses an admitted participant blocked by the author',
        () async {
          await expectLater(
            useCase.list(beaconId: _openRequest, userId: _blockedMember),
            throwsA(isA<UnauthorizedException>()),
          );
        },
      );

      test('history refuses the author of a deleted beacon', () async {
        await expectLater(
          useCase.history(
            factCardId: _deletedRequestFact,
            beaconId: _deletedRequest,
            userId: _author,
          ),
          throwsA(isA<UnauthorizedException>()),
        );
      });

      test(
        'an admitted participant who is not blocked is not refused',
        () async {
          final facts = await useCase.list(
            beaconId: _openRequest,
            userId: _member,
          );
          expect(facts, hasLength(1));
        },
      );
    },
  );
}

class _UnusedImage extends Fake implements ImageRepositoryPort {}

class _UnusedTasks extends Fake implements TaskRepositoryPort {}

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

  for (final (id, beaconId) in [
    (_openRequestFact, _openRequest),
    (_deletedRequestFact, _deletedRequest),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq)
VALUES (@id, @beacon, 'Original', ${BeaconFactCardVisibilityBits.public},
        @author, ${BeaconFactCardStatusBits.active}, 1)
'''),
      parameters: {'id': id, 'beacon': beaconId, 'author': _author},
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind)
VALUES (@id, 1, 'Original', @author,
        ${BeaconFactCardRevisionKindBits.created})
'''),
      parameters: {'id': id, 'author': _author},
    );
  }

  await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_author', '$_blockedMember', '$_blockedMember')
''');
}
