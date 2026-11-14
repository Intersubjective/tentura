@Tags(['pg'])
library;

import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/image_object_gc_repository.dart';
import 'package:tentura_server/data/repository/image_repository.dart';
import 'package:tentura_server/data/repository/upload_quota_repository.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/domain/use_case/beacon_fact_card_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/beacon_repository_ctor_arg.dart';
import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';

/// Facts copied into a draft Request stay silent until the draft is
/// published. Publishing announces them once: one "facts brought" chat line
/// (marker 20) by the publishing author and one `factPinned` event per
/// copied fact. Real repositories over a disposable Postgres; the copies are
/// made through the real copy use case.

String _publicKey(int world, int slot) =>
    'fcpub${world}w${slot}s'.padRight(44, 'q');

final class _Storage extends Fake implements RemoteStoragePort {}

final class _Tasks extends Fake implements TaskRepositoryPort {
  @override
  Future<String> schedule(TaskEntity task) async => 'task';
}

/// One isolated set of users and beacons per test. The actor owns the
/// drafts and is an admitted member of the source Request; the author owns
/// the source Request and its facts.
final class _World {
  _World(this.n);

  final int n;

  String _id(String prefix) => '$prefix${'pb$n'.padLeft(11, '0')}';

  String get author => _id('Ua');
  String get actor => _id('Uc');

  String get source => _id('Bs');
  String get parent => _id('Bp');
  String get draft => _id('Bd');
  String get childDraft => _id('Bc');
  String get openChild => _id('Bb');
  String get openRequest => _id('Bo');

  String sourceFact(int i) => _id('F$i');
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PUBLISH_ANNOUNCES_FACTS_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_publish_announces_facts',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb db;
  late BeaconRepository beacons;
  late BeaconFactCardCase facts;
  var worlds = 0;

  Future<List<Map<String, Object?>>> rows(
    String sql, [
    Map<String, Object?> parameters = const {},
  ]) async {
    final result = await writer.execute(Sql.named(sql), parameters: parameters);
    return [for (final r in result) r.toColumnMap()];
  }

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    db = TenturaDb.forTest(
      database: PgDatabase.opened(
        Pool<dynamic>.withEndpoints(
          [target.databaseEnv.pgEndpoint],
          settings: target.databaseEnv.pgPoolSettings,
        ),
        enableMigrations: false,
      ),
    );
  });

  setUp(() {
    final env = Env(environment: Environment.test);
    final logger = Logger('BeaconPublishAnnouncesCopiedFactsPgTest');
    final storage = _Storage();
    final room = BeaconRoomRepository(db);
    final gc = ImageObjectGcRepository(db, storage);
    final images = ImageRepository(
      db,
      storage,
      UploadQuotaRepository(db),
      gc,
      env,
      logger,
    );
    beacons = BeaconRepository(db);
    facts = buildWithBeaconRepository<BeaconFactCardCase>(
      BeaconFactCardCase.new,
      positional: [
        BeaconFactCardRepository(db, room),
        room,
        images,
        _Tasks(),
        BeaconHierarchyRepository(db),
        FakeBeaconAccessGuard(),
      ],
      named: {#env: env, #logger: logger},
      beaconRepository: beacons,
    );
  });

  tearDownAll(() => tearDownDisposablePgWriter(session: session, drift: db));

  /// Inserts a live fact row and its first revision directly. With
  /// [originFactCardId] the row looks like a copy coming from a beacon of
  /// [originBeaconKind]; without it, it is an ordinary fact (null origin).
  Future<void> seedFact({
    required String id,
    required String beaconId,
    required String pinnedBy,
    String? text,
    String? originFactCardId,
    int originBeaconKind = 0,
  }) async {
    final factText = text ?? 'Fact $id';
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card
  (id, beacon_id, fact_text, visibility, pinned_by, status, revision_seq,
   origin_fact_card_id, origin_revision_seq, origin_beacon_kind)
VALUES (@id, @beacon, @text, ${BeaconFactCardVisibilityBits.public}, @by,
        ${BeaconFactCardStatusBits.active}, 1, @origin::text,
        CASE WHEN @origin::text IS NULL THEN NULL ELSE 1 END,
        CASE WHEN @origin::text IS NULL THEN NULL
             ELSE @kind::smallint END)
'''),
      parameters: {
        'id': id,
        'beacon': beaconId,
        'text': factText,
        'by': pinnedBy,
        'origin': originFactCardId,
        'kind': originBeaconKind,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_fact_card_revision
  (fact_card_id, seq, fact_text, actor_id, kind, attachments_json)
VALUES (@id, 1, @text, @by, @kind, '[]'::jsonb)
'''),
      parameters: {
        'id': id,
        'text': factText,
        'by': pinnedBy,
        'kind': originFactCardId == null
            ? BeaconFactCardRevisionKindBits.created
            : BeaconFactCardRevisionKindBits.copied,
      },
    );
  }

  /// [sourceTexts] become the facts of the published source Request.
  Future<_World> world({
    List<String> sourceTexts = const ['First fact', 'Second fact'],
  }) async {
    final w = _World(++worlds);
    for (final (i, user) in [w.author, w.actor].indexed) {
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          'VALUES (@id, @id, @key)',
        ),
        parameters: {'id': user, 'key': _publicKey(w.n, i + 1)},
      );
    }
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES (@source, @author, 'Source', 'd', 0, 0, now(), false),
       (@parent, @actor, 'Parent', 'd', 0, 0, now(), false),
       (@open, @actor, 'Already open', 'd', 0, 0, now(), false),
       (@draft, @actor, 'Own draft', 'd', 3, 0, NULL, false)
'''),
      parameters: {
        'source': w.source,
        'parent': w.parent,
        'open': w.openRequest,
        'draft': w.draft,
        'author': w.author,
        'actor': w.actor,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable, parent_beacon_id)
VALUES (@child, @actor, 'Child draft', 'd', 3, 0, NULL, false, @parent),
       (@openChild, @actor, 'Bud', 'd', 0, 0, now(), false, @parent)
'''),
      parameters: {
        'child': w.childDraft,
        'openChild': w.openChild,
        'parent': w.parent,
        'actor': w.actor,
      },
    );
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES (@id, @beacon, @user, 0, 0, ${RoomAccessBits.admitted})
'''),
      parameters: {'id': 'Ppb${w.n}x0', 'beacon': w.source, 'user': w.actor},
    );
    for (final (i, text) in sourceTexts.indexed) {
      await seedFact(
        id: w.sourceFact(i),
        beaconId: w.source,
        pinnedBy: w.author,
        text: text,
      );
    }
    return w;
  }

  /// Copies source facts [indexes] into [beaconId] through the copy use case;
  /// returns the new fact ids in copy order.
  Future<List<String>> copyInto(
    _World w,
    String beaconId,
    List<int> indexes,
  ) async => [
    for (final i in indexes)
      (await facts.copy(
        sourceFactCardId: w.sourceFact(i),
        destinationBeaconId: beaconId,
        actorUserId: w.actor,
      )).factCardId,
  ];

  Future<List<Map<String, Object?>>> factLines(String beaconId) => rows(
    '''
SELECT id, author_id, body, beacon_id, semantic_marker,
       system_payload::text AS payload
FROM public.beacon_room_message
WHERE beacon_id = @b
  AND semantic_marker = ${BeaconRoomSemanticMarker.factsBrought}
ORDER BY created_at, id
''',
    {'b': beaconId},
  );

  Future<List<Map<String, Object?>>> factPinnedEvents(String beaconId) => rows(
    '''
SELECT type, visibility, actor_id, source_message_id, fact_card_id,
       diff::text AS diff
FROM public.beacon_activity_event
WHERE beacon_id = @b AND type = ${BeaconActivityEventTypeBits.factPinned}
ORDER BY fact_card_id
''',
    {'b': beaconId},
  );

  Map<String, Object?> payloadOf(Map<String, Object?> line) =>
      (jsonDecode(line['payload']! as String) as Map).cast<String, Object?>();

  Future<String> factTextOf(String factId) async =>
      (await rows(
            'SELECT fact_text FROM public.beacon_fact_card WHERE id = @f',
            {'f': factId},
          )).single['fact_text']!
          as String;

  /// Checks one `factPinned` event per id in [factIds], each pointing at
  /// [lineId], by [actor], with the fact's own text in its diff.
  Future<void> expectPinnedEvents(
    String beaconId, {
    required String lineId,
    required String actor,
    required List<String> factIds,
  }) async {
    final events = await factPinnedEvents(beaconId);
    expect(
      [for (final e in events) e['fact_card_id']],
      unorderedEquals(factIds),
      reason: 'exactly one factPinned event per announced fact',
    );
    for (final e in events) {
      final factId = e['fact_card_id']! as String;
      expect(e['type'], BeaconActivityEventTypeBits.factPinned);
      expect(e['visibility'], BeaconActivityEventVisibilityBits.room);
      expect(e['actor_id'], actor);
      expect(e['source_message_id'], lineId);
      expect(jsonDecode(e['diff']! as String), {
        'factCardId': factId,
        'factText': await factTextOf(factId),
      });
    }
  }

  group('Publishing a standalone draft Request announces its copied facts', () {
    test('two copied facts: one marker-20 line by the author with count 2, '
        'and one factPinned event per fact', () async {
      final w = await world();
      final copies = await copyInto(w, w.draft, [0, 1]);
      expect(await factLines(w.draft), isEmpty, reason: 'silent while draft');

      await beacons.publishDraft(id: w.draft, actorId: w.actor);

      final lines = await factLines(w.draft);
      expect(lines, hasLength(1));
      final line = lines.single;
      expect(line['semantic_marker'], BeaconRoomSemanticMarker.factsBrought);
      expect(line['author_id'], w.actor);
      expect(line['body'], '');
      expect(line['beacon_id'], w.draft);
      final payload = payloadOf(line);
      expect(
        payload.keys,
        unorderedEquals(['factCardIds', 'count', 'originBeaconKind']),
      );
      expect(payload['factCardIds'], unorderedEquals(copies));
      expect(payload['count'], 2);
      expect(payload['originBeaconKind'], 0);
      await expectPinnedEvents(
        w.draft,
        lineId: line['id']! as String,
        actor: w.actor,
        factIds: copies,
      );
    });

    test('one long copied fact: count 1 and factText cut to 160 '
        'characters', () async {
      final longText = List.filled(30, 'abcdefg').join(' ');
      expect(longText.length, greaterThan(160));
      final w = await world(sourceTexts: [longText]);
      final copies = await copyInto(w, w.draft, [0]);

      await beacons.publishDraft(id: w.draft, actorId: w.actor);

      final line = (await factLines(w.draft)).single;
      final payload = payloadOf(line);
      expect(payload['count'], 1);
      expect(payload['factCardIds'], copies);
      expect(payload['factText'], longText.substring(0, 160));
      await expectPinnedEvents(
        w.draft,
        lineId: line['id']! as String,
        actor: w.actor,
        factIds: copies,
      );
    });

    test('facts copied from a Post and from a Request: originBeaconKind is '
        'null', () async {
      final w = await world(sourceTexts: ['From a Request']);
      final fromRequest = await copyInto(w, w.draft, [0]);
      final fromPost = 'Fpm${'pb${w.n}'.padLeft(11, '0')}';
      await seedFact(
        id: fromPost,
        beaconId: w.draft,
        pinnedBy: w.actor,
        text: 'From a Post',
        originFactCardId: 'Fpostorigin${w.n}',
        originBeaconKind: 1,
      );

      await beacons.publishDraft(id: w.draft, actorId: w.actor);

      final payload = payloadOf((await factLines(w.draft)).single);
      expect(payload['count'], 2);
      expect(payload, containsPair('originBeaconKind', null));
      expect(
        payload['factCardIds'],
        unorderedEquals([...fromRequest, fromPost]),
      );
      await expectPinnedEvents(
        w.draft,
        lineId: (await factLines(w.draft)).single['id']! as String,
        actor: w.actor,
        factIds: [...fromRequest, fromPost],
      );
    });

    test('a copied fact removed from the draft before publishing is not '
        'announced', () async {
      final w = await world(sourceTexts: ['One', 'Two', 'Three']);
      final copies = await copyInto(w, w.draft, [0, 1, 2]);
      expect(
        await facts.remove(
          factCardId: copies[1],
          beaconId: w.draft,
          actorUserId: w.actor,
        ),
        isTrue,
      );

      await beacons.publishDraft(id: w.draft, actorId: w.actor);

      final line = (await factLines(w.draft)).single;
      final payload = payloadOf(line);
      expect(payload['count'], 2);
      expect(payload['factCardIds'], unorderedEquals([copies[0], copies[2]]));
      await expectPinnedEvents(
        w.draft,
        lineId: line['id']! as String,
        actor: w.actor,
        factIds: [copies[0], copies[2]],
      );
    });

    test('a fact without an origin is not announced next to a copied '
        'one', () async {
      final w = await world(sourceTexts: ['Copied']);
      final copies = await copyInto(w, w.draft, [0]);
      final plain = 'Fpl${'pb${w.n}'.padLeft(11, '0')}';
      await seedFact(id: plain, beaconId: w.draft, pinnedBy: w.actor);

      await beacons.publishDraft(id: w.draft, actorId: w.actor);

      final line = (await factLines(w.draft)).single;
      final payload = payloadOf(line);
      expect(payload['count'], 1);
      expect(payload['factCardIds'], copies);
      await expectPinnedEvents(
        w.draft,
        lineId: line['id']! as String,
        actor: w.actor,
        factIds: copies,
      );
    });

    test('a draft without copied facts gets no line and no event', () async {
      final w = await world();
      await seedFact(
        id: 'Fpn${'pb${w.n}'.padLeft(11, '0')}',
        beaconId: w.draft,
        pinnedBy: w.actor,
      );

      await beacons.publishDraft(id: w.draft, actorId: w.actor);

      expect(await factLines(w.draft), isEmpty);
      expect(await factPinnedEvents(w.draft), isEmpty);
    });

    test('publishing again does not repeat the line', () async {
      final w = await world();
      await copyInto(w, w.draft, [0, 1]);

      await beacons.publishDraft(id: w.draft, actorId: w.actor);
      await beacons.publishDraft(id: w.draft, actorId: w.actor);

      expect(await factLines(w.draft), hasLength(1));
      expect(await factPinnedEvents(w.draft), hasLength(2));
    });

    test('publishing an already open Request writes nothing', () async {
      final w = await world();
      for (final i in [0, 1]) {
        await seedFact(
          id: 'Fpo$i${'pb${w.n}'.padLeft(10, '0')}',
          beaconId: w.openRequest,
          pinnedBy: w.actor,
          originFactCardId: w.sourceFact(i),
        );
      }

      await beacons.publishDraft(id: w.openRequest, actorId: w.actor);

      expect(await factLines(w.openRequest), isEmpty);
      expect(await factPinnedEvents(w.openRequest), isEmpty);
    });
  });

  group('Publishing a child draft announces its copied facts', () {
    test('two copied facts: one marker-20 line with count 2 and two '
        'factPinned events', () async {
      final w = await world();
      final copies = await copyInto(w, w.childDraft, [0, 1]);
      expect(await factLines(w.childDraft), isEmpty);

      await beacons.publishChildDraft(
        childBeaconId: w.childDraft,
        actorId: w.actor,
      );

      final lines = await factLines(w.childDraft);
      expect(lines, hasLength(1));
      final line = lines.single;
      expect(line['author_id'], w.actor);
      expect(line['body'], '');
      final payload = payloadOf(line);
      expect(payload['count'], 2);
      expect(payload['factCardIds'], unorderedEquals(copies));
      expect(payload['originBeaconKind'], 0);
      await expectPinnedEvents(
        w.childDraft,
        lineId: line['id']! as String,
        actor: w.actor,
        factIds: copies,
      );

      await beacons.publishChildDraft(
        childBeaconId: w.childDraft,
        actorId: w.actor,
      );
      expect(await factLines(w.childDraft), hasLength(1));
    });

    test('a child draft without copied facts gets no line and no '
        'event', () async {
      final w = await world();
      await seedFact(
        id: 'Fpk${'pb${w.n}'.padLeft(11, '0')}',
        beaconId: w.childDraft,
        pinnedBy: w.actor,
      );

      await beacons.publishChildDraft(
        childBeaconId: w.childDraft,
        actorId: w.actor,
      );

      expect(await factLines(w.childDraft), isEmpty);
      expect(await factPinnedEvents(w.childDraft), isEmpty);
    });

    test('a child created already open (a bud) gets no line from '
        'publish', () async {
      final w = await world();
      for (final i in [0, 1]) {
        await seedFact(
          id: 'Fpb$i${'pb${w.n}'.padLeft(10, '0')}',
          beaconId: w.openChild,
          pinnedBy: w.actor,
          originFactCardId: w.sourceFact(i),
        );
      }

      await beacons.publishChildDraft(
        childBeaconId: w.openChild,
        actorId: w.actor,
      );

      expect(await factLines(w.openChild), isEmpty);
      expect(await factPinnedEvents(w.openChild), isEmpty);
    });
  });
}
