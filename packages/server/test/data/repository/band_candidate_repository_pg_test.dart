@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/band_candidate_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/env.dart';

const _ego = 'Ucapd0ego01';
const _author = 'Ucapd0auth01';
const _other = 'Ucapd0other1';
const _beaconId = 'Bcapd0bcn001';
const _ctx = '';

const _unseen = 'Ucapd0unsee1';
const _helpOffered = 'Ucapd0help01';
const _withdrawn = 'Ucapd0withd1';
const _watching = 'Ucapd0watch1';
const _forwardedTo = 'Ucapd0forwd1';
const _onward = 'Ucapd0onwrd1';
const _declined = 'Ucapd0decl01';
const _myForwarded = 'Ucapd0myfwd1';
const _blocked = 'Ucapd0block1';

const _allIds = [
  _ego,
  _author,
  _other,
  _unseen,
  _helpOffered,
  _withdrawn,
  _watching,
  _forwardedTo,
  _onward,
  _declined,
  _myForwarded,
  _blocked,
];

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late BandCandidateRepository repo;
  late MeritrankRepository meritRank;
  late HelpOfferRepository helpOfferRepo;

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      meritRank = MeritrankRepository(database);
      helpOfferRepo = HelpOfferRepository(database);
      repo = BandCandidateRepository(
        database,
        ForwardEdgeRepository(database),
        helpOfferRepo,
        InboxRepository(database),
      );
    });

    setUp(() async {
      await _cleanup(database, meritRank);
      for (final id in _allIds) {
        await _insertUser(database, id);
      }
      await _insertBeacon(database);
    });

    tearDown(() async {
      await _cleanup(database, meritRank);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  group('BandCandidateRepository', () {
    test(
      'candidatesFor mirrors Forward screen involvement precedence',
      () async {
        await _seedVisibility(meritRank, database);
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@ego, @blocked, @blocked)
ON CONFLICT DO NOTHING
'''),
          parameters: {'ego': _ego, 'blocked': _blocked},
        );

        await helpOfferRepo.upsert(
          beaconId: _beaconId,
          userId: _helpOffered,
        );
        await helpOfferRepo.upsert(
          beaconId: _beaconId,
          userId: _withdrawn,
        );
        await helpOfferRepo.withdraw(
          beaconId: _beaconId,
          userId: _withdrawn,
          withdrawReason: 'changed mind',
        );

        await writer.execute(
          Sql.named(r'''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at, latest_note_preview, rejection_message
) VALUES
  (@watching, @beacon, 1, 0, '2026-01-02T00:00:00Z', '', ''),
  (@declined, @beacon, 2, 0, '2026-01-03T00:00:00Z', '', 'no')
ON CONFLICT (user_id, beacon_id) DO UPDATE SET status = EXCLUDED.status
'''),
          parameters: {
            'watching': _watching,
            'declined': _declined,
            'beacon': _beaconId,
          },
        );

        await _insertForwardEdge(
          writer,
          id: 'Fcapd0forwd1',
          senderId: _other,
          recipientId: _forwardedTo,
        );
        await _insertForwardEdge(
          writer,
          id: 'Fcapd0onwrd1',
          senderId: _onward,
          recipientId: _unseen,
        );
        await _insertForwardEdge(
          writer,
          id: 'Fcapd0myfwd1',
          senderId: _ego,
          recipientId: _myForwarded,
        );

        final candidates = await repo.candidatesFor(
          egoId: _ego,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );
        final byId = {for (final c in candidates) c.userId: c};

        expect(byId.keys, containsAll([
          _unseen,
          _helpOffered,
          _withdrawn,
          _watching,
          _forwardedTo,
          _onward,
        ]));
        expect(byId.keys, isNot(contains(_author)));
        expect(byId.keys, isNot(contains(_declined)));
        expect(byId.keys, isNot(contains(_myForwarded)));
        expect(byId.keys, isNot(contains(_blocked)));

        expect(byId[_unseen]!.canForwardTo, isTrue);
        expect(byId[_watching]!.canForwardTo, isTrue);
        expect(byId[_forwardedTo]!.canForwardTo, isTrue);
        expect(byId[_onward]!.canForwardTo, isTrue);
        expect(byId[_helpOffered]!.canForwardTo, isFalse);
        expect(byId[_withdrawn]!.canForwardTo, isFalse);

        expect(byId[_myForwarded], isNull);
        for (final c in candidates) {
          expect(c.alreadyForwarded, isFalse);
        }
        expect(
          candidates.map((c) => c.forwardMr).toList(),
          equals(
            [...candidates.map((c) => c.forwardMr)]
              ..sort((a, b) => b.compareTo(a)),
          ),
        );
      },
      skip: skipReason,
    );

    test(
      'candidatesFor excludes blocked peers via person_visibility_peers',
      () async {
        await _mrEdge(meritRank, _ego, _unseen, 0.8);
        await _trustBothWays(database, _ego, _unseen);
        await _mrEdge(meritRank, _ego, _blocked, 0.9);
        await _trustBothWays(database, _ego, _blocked);
        await writer.execute(
          Sql.named(r'''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@ego, @blocked, @blocked)
ON CONFLICT DO NOTHING
'''),
          parameters: {'ego': _ego, 'blocked': _blocked},
        );

        final candidates = await repo.candidatesFor(
          egoId: _ego,
          beaconId: _beaconId,
          normalizedContext: _ctx,
        );

        expect(candidates.map((c) => c.userId), contains(_unseen));
        expect(candidates.map((c) => c.userId), isNot(contains(_blocked)));
      },
      skip: skipReason,
    );

    test(
      'recentlyForwardedTo respects window and includes cancelled edges',
      () async {
        final recentActive = 'Ucapd0reca01';
        final recentCancelled = 'Ucapd0recc01';
        final oldRecipient = 'Ucapd0oldr01';
        for (final id in [recentActive, recentCancelled, oldRecipient]) {
          await _insertUser(database, id);
        }

        await writer.execute(
          Sql.named(r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES
  ('Fcapd0reca1', @beacon, @ego, @recentActive,
   now() - interval '2 days', NULL),
  ('Fcapd0recc1', @beacon, @ego, @recentCancelled,
   now() - interval '2 days', now() - interval '1 day'),
  ('Fcapd0oldr1', @beacon, @ego, @oldRecipient,
   now() - interval '30 days', NULL)
'''),
          parameters: {
            'beacon': _beaconId,
            'ego': _ego,
            'recentActive': recentActive,
            'recentCancelled': recentCancelled,
            'oldRecipient': oldRecipient,
          },
        );

        final withinWeek = await repo.recentlyForwardedTo(
          egoId: _ego,
          withinDays: 7,
        );
        expect(withinWeek, containsAll([recentActive, recentCancelled]));
        expect(withinWeek, isNot(contains(oldRecipient)));

        final withinDay = await repo.recentlyForwardedTo(
          egoId: _ego,
          withinDays: 1,
        );
        expect(withinDay, isEmpty);
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedVisibility(MeritrankRepository meritRank, TenturaDb db) async {
  final peers = [
    _unseen,
    _helpOffered,
    _withdrawn,
    _watching,
    _forwardedTo,
    _onward,
    _declined,
    _myForwarded,
    _blocked,
  ];
  var weight = 0.95;
  for (final peer in peers) {
    await _mrEdge(meritRank, _ego, peer, weight);
    await _trustBothWays(db, _ego, peer);
    weight -= 0.05;
  }
}

Future<void> _trustBothWays(TenturaDb db, String a, String b) async {
  await _trustEdge(db, a, b);
  await _trustEdge(db, b, a);
}

Future<void> _trustEdge(TenturaDb db, String subject, String object) =>
    db.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$subject', '$object', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (subject, object) DO UPDATE SET amount = EXCLUDED.amount
''');

Future<void> _insertUser(TenturaDb db, String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

Future<void> _insertBeacon(TenturaDb db) => db.customStatement('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_beaconId', '$_author', 'Band candidate beacon', 'd', 0)
ON CONFLICT (id) DO NOTHING
''');

Future<void> _insertForwardEdge(
  Connection writer, {
  required String id,
  required String senderId,
  required String recipientId,
}) => writer.execute(
  Sql.named(r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  @id, @beacon, @sender, @recipient, '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
'''),
  parameters: {
    'id': id,
    'beacon': _beaconId,
    'sender': senderId,
    'recipient': recipientId,
  },
);

Future<void> _mrEdge(
  MeritrankRepository meritRank,
  String subject,
  String object,
  double weight,
) => meritRank.putEdge(nodeA: subject, nodeB: object, weight: weight);

Future<void> _clearMrEdge(TenturaDb db, String subject, String object) =>
    db.customStatement(
      "SELECT mr_put_edge('$subject', '$object', 0::double precision, ''::text, 0)",
    );

Future<void> _cleanup(TenturaDb db, MeritrankRepository meritRank) async {
  final peers = [
    _unseen,
    _helpOffered,
    _withdrawn,
    _watching,
    _forwardedTo,
    _onward,
    _declined,
    _myForwarded,
    _blocked,
    'Ucapd0reca01',
    'Ucapd0recc01',
    'Ucapd0oldr01',
  ];
  for (final peer in peers) {
    await _clearMrEdge(db, _ego, peer);
    await _clearMrEdge(db, peer, _ego);
  }
  final idList = [..._allIds, ...peers].toSet().map((id) => "'$id'").join(', ');
  await db.customStatement(
    'DELETE FROM public.beacon_forward_edge WHERE beacon_id = \'$_beaconId\'',
  );
  await db.customStatement(
    'DELETE FROM public.beacon_help_offer WHERE beacon_id = \'$_beaconId\'',
  );
  await db.customStatement(
    'DELETE FROM public.inbox_item WHERE beacon_id = \'$_beaconId\'',
  );
  await db.customStatement(
    'DELETE FROM public.user_block '
    'WHERE blocker_id IN ($idList) OR blocked_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.beacon WHERE id = \'$_beaconId\'',
  );
  await db.customStatement(
    'DELETE FROM public."user" WHERE id IN ($idList)',
  );
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_BAND_CANDIDATE_REPO_TEST_DB'] ??
        'tentura_test_band_candidate_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_BAND_CANDIDATE_REPO_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
