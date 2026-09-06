import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/env.dart';

import 'pg_test_public_keys.dart';

/// Canonical A→B→C plus A→D topology from nested-requests plan §3.2.
///
/// `parent_beacon_id` is persisted from Task 02 (`m0154`); until nested edges are
/// seeded, [BeaconHierarchyTopology.intendedParentByChild] documents intended edges.
/// for authorization and hierarchy tests.
final class BeaconHierarchyTopology {
  const BeaconHierarchyTopology();

  static const aliceId = 'Uhieralice01';
  static const bobId = 'Uhierbob0001';
  static const carolId = 'Uhiercarol01';
  static const daveId = 'Uhierdave001';
  static const eveId = 'Uhiereve0001';
  static const frankId = 'Uhierfrank01';

  static const beaconA = 'BhierA000001';
  static const beaconB = 'BhierB000001';
  static const beaconC = 'BhierC000001';
  static const beaconD = 'BhierD000001';
  static const privateDraftChildId = 'Bhierdraft001';

  static const generalMessageOnA = 'Rhiergenmsg01';
  static const retiredAskItemId = 'Ihieraskret01';
  static const supportedPlanItemId = 'Ihierplan001';
  static const retiredAskThreadMessageId = 'Rhieraskth01';

  /// Child beacon ID → intended parent beacon ID (null = root / standalone).
  static const Map<String, String?> intendedParentByChild = {
    beaconB: beaconA,
    beaconC: beaconB,
    beaconD: beaconA,
  };

  static const allBeaconIds = [
    beaconA,
    beaconB,
    beaconC,
    beaconD,
    privateDraftChildId,
  ];

  static const allUserIds = [
    aliceId,
    bobId,
    carolId,
    daveId,
    eveId,
    frankId,
  ];
}

/// Disposable Postgres target for nested-request PG tests.
///
/// Uses env `TENTURA_BEACON_HIERARCHY_PG_TEST_DB` when set; otherwise allocates
/// `tentura_test_bhier_<pid>_<micros>`.
final class BeaconHierarchyDisposablePgTarget {
  const BeaconHierarchyDisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  /// [databaseNameOverride] forces a specific disposable name, bypassing
  /// `TENTURA_BEACON_HIERARCHY_PG_TEST_DB`. Use it whenever a single test
  /// process needs more than one disposable target at once (e.g. an
  /// upgrade-path test alongside the suite's own `setUpAll` target) — two
  /// calls to `fromEnvironment()` with the env var set would otherwise
  /// resolve to the *same* name, and a later `recreate()`/`drop()` would
  /// `DROP DATABASE` out from under the other target's live connection.
  factory BeaconHierarchyDisposablePgTarget.fromEnvironment({
    String? databaseNameOverride,
  }) {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        databaseNameOverride ??
        Platform.environment['TENTURA_BEACON_HIERARCHY_PG_TEST_DB'] ??
        'tentura_test_bhier_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_BEACON_HIERARCHY_PG_TEST_DB',
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

    return BeaconHierarchyDisposablePgTarget(
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
        'DROP DATABASE IF EXISTS $databaseName WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE $databaseName');
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
        'DROP DATABASE IF EXISTS $databaseName WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}

/// Seeds the §3.2 hierarchy fixture on a disposable database.
///
/// Inserts use the writer [Connection] directly (privileged test path). Runtime
/// authorization tests must go through domain cases/repositories on [db].
final class BeaconHierarchyFixture {
  BeaconHierarchyFixture({
    required this.writer,
    required this.db,
    this.topology = const BeaconHierarchyTopology(),
  });

  final Connection writer;
  final TenturaDb db;
  final BeaconHierarchyTopology topology;

  Future<void> seedFullTopology() async {
    await _seedUsers();
    await _seedPublishedBeacons();
    await _seedPrivateDraftChild();
    await _seedAdmissions();
    await _seedHelpOffers();
    await _seedForwardToAliceForB();
    await _seedSupportedAndRetiredCoordination();
    await _seedGeneralAndRetiredThreadMessages();
  }

  Future<void> tearDown() async {
    await writer.execute(
      "DELETE FROM public.beacon_room_message_attachment WHERE message_id LIKE 'Rhier%'",
    );
    await writer.execute(
      "DELETE FROM public.beacon_room_message WHERE id LIKE 'Rhier%' OR beacon_id LIKE 'Bhier%'",
    );
    await writer.execute(
      "DELETE FROM public.beacon_room_seen WHERE beacon_id LIKE 'Bhier%'",
    );
    await writer.execute(
      "DELETE FROM public.beacon_fact_card WHERE beacon_id LIKE 'Bhier%'",
    );
    await writer.execute(
      "DELETE FROM public.polling_variant WHERE polling_id LIKE 'Phier%'",
    );
    await writer.execute(
      "DELETE FROM public.polling WHERE id LIKE 'Phier%'",
    );
    await writer.execute(
      "DELETE FROM public.coordination_item WHERE beacon_id LIKE 'Bhier%'",
    );
    await writer.execute(
      "DELETE FROM public.beacon_forward_edge WHERE beacon_id LIKE 'Bhier%'",
    );
    await writer.execute(
      "DELETE FROM public.beacon_help_offer WHERE beacon_id LIKE 'Bhier%'",
    );
    await writer.execute(
      "DELETE FROM public.beacon_participant WHERE beacon_id LIKE 'Bhier%'",
    );
    await writer.execute(
      "DELETE FROM public.beacon WHERE id LIKE 'Bhier%'",
    );
    await writer.execute(
      "DELETE FROM public.\"user\" WHERE id LIKE 'Uhier%'",
    );
  }

  Future<void> _seedUsers() async {
    final users = <(String, int)>[
      (BeaconHierarchyTopology.aliceId, 1),
      (BeaconHierarchyTopology.bobId, 2),
      (BeaconHierarchyTopology.carolId, 3),
      (BeaconHierarchyTopology.daveId, 4),
      (BeaconHierarchyTopology.eveId, 5),
      (BeaconHierarchyTopology.frankId, 6),
    ];
    for (final entry in users) {
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'id': entry.$1,
          'publicKey': pgTestPublicKey('bhier', entry.$2),
        },
      );
    }
  }

  Future<void> _seedPublishedBeacons() async {
    final rows = <(String, String, String)>[
      (BeaconHierarchyTopology.beaconA, BeaconHierarchyTopology.aliceId, 'Request A'),
      (BeaconHierarchyTopology.beaconB, BeaconHierarchyTopology.bobId, 'Request B'),
      (BeaconHierarchyTopology.beaconC, BeaconHierarchyTopology.daveId, 'Request C'),
      (BeaconHierarchyTopology.beaconD, BeaconHierarchyTopology.eveId, 'Request D'),
    ];
    for (final row in rows) {
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, published_at, created_at, updated_at
) VALUES (
  @id, @ownerId, @title, '', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {'id': row.$1, 'ownerId': row.$2, 'title': row.$3},
      );
    }
  }

  Future<void> _seedPrivateDraftChild() async {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, created_at, updated_at
) VALUES (
  @id, @ownerId, 'Private child draft', '', 3,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
'''),
      parameters: {
        'id': BeaconHierarchyTopology.privateDraftChildId,
        'ownerId': BeaconHierarchyTopology.bobId,
      },
    );
  }

  Future<void> _seedAdmissions() async {
    await _insertParticipant(
      id: 'PhieraliceA01',
      beaconId: BeaconHierarchyTopology.beaconA,
      userId: BeaconHierarchyTopology.aliceId,
      roomAccess: RoomAccessBits.admitted,
    );
    await _insertParticipant(
      id: 'PhiercarolC01',
      beaconId: BeaconHierarchyTopology.beaconC,
      userId: BeaconHierarchyTopology.carolId,
      roomAccess: RoomAccessBits.admitted,
    );
    await _insertParticipant(
      id: 'PhierbobB01',
      beaconId: BeaconHierarchyTopology.beaconB,
      userId: BeaconHierarchyTopology.bobId,
      roomAccess: RoomAccessBits.admitted,
    );
  }

  Future<void> _insertParticipant({
    required String id,
    required String beaconId,
    required String userId,
    required int roomAccess,
  }) async {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon_participant (
  id, beacon_id, user_id, role, status, room_access, created_at, updated_at
) VALUES (
  @id, @beaconId, @userId, 0, 0, @roomAccess,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT DO NOTHING
'''),
      parameters: {
        'id': id,
        'beaconId': beaconId,
        'userId': userId,
        'roomAccess': roomAccess,
      },
    );
  }

  Future<void> _seedHelpOffers() async {
    final offers = <(String, String)>[
      (BeaconHierarchyTopology.beaconA, BeaconHierarchyTopology.frankId),
      (BeaconHierarchyTopology.beaconB, BeaconHierarchyTopology.aliceId),
      (BeaconHierarchyTopology.beaconC, BeaconHierarchyTopology.bobId),
      (BeaconHierarchyTopology.beaconD, BeaconHierarchyTopology.carolId),
    ];
    for (final offer in offers) {
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, help_type, status, offer_kind, stake_state
) VALUES (
  @beaconId, @userId, '', '[]', 0, 0, 0
)
ON CONFLICT (beacon_id, user_id) DO NOTHING
'''),
        parameters: {'beaconId': offer.$1, 'userId': offer.$2},
      );
    }
  }

  Future<void> _seedForwardToAliceForB() async {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'FhierfwdB01', @beaconId, @senderId, @recipientId,
  '2026-01-02T00:00:00Z'
)
ON CONFLICT DO NOTHING
'''),
      parameters: {
        'beaconId': BeaconHierarchyTopology.beaconB,
        'senderId': BeaconHierarchyTopology.frankId,
        'recipientId': BeaconHierarchyTopology.aliceId,
      },
    );
  }

  Future<void> _seedSupportedAndRetiredCoordination() async {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  published, created_at, updated_at, published_at, source, ordering
) VALUES (
  @id, @beaconId, @kind, @status, @title, '', @creatorId, @targetId,
  true, '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z',
  0, 0
)
ON CONFLICT (id) DO NOTHING
'''),
      parameters: {
        'id': BeaconHierarchyTopology.supportedPlanItemId,
        'beaconId': BeaconHierarchyTopology.beaconA,
        'kind': coordinationItemKindPlan,
        'status': coordinationItemStatusOpen,
        'title': 'Supported plan',
        'creatorId': BeaconHierarchyTopology.aliceId,
        'targetId': BeaconHierarchyTopology.bobId,
      },
    );
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  published, created_at, updated_at, published_at, source, ordering
) VALUES (
  @id, @beaconId, @kind, @status, @title, '', @creatorId, @targetId,
  true, '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z',
  0, 1
)
ON CONFLICT (id) DO NOTHING
'''),
      parameters: {
        'id': BeaconHierarchyTopology.retiredAskItemId,
        'beaconId': BeaconHierarchyTopology.beaconA,
        'kind': coordinationItemKindAsk,
        'status': coordinationItemStatusOpen,
        'title': 'Retired ask fixture',
        'creatorId': BeaconHierarchyTopology.aliceId,
        'targetId': BeaconHierarchyTopology.bobId,
      },
    );
  }

  Future<void> _seedGeneralAndRetiredThreadMessages() async {
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, thread_item_id, created_at
) VALUES (
  @id, @beaconId, @authorId, @body, NULL, '2026-01-03T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
'''),
      parameters: {
        'id': BeaconHierarchyTopology.generalMessageOnA,
        'beaconId': BeaconHierarchyTopology.beaconA,
        'authorId': BeaconHierarchyTopology.aliceId,
        'body': 'General message on A for promotion source fixture',
      },
    );
    await writer.execute(
      Sql.named(r'''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, thread_item_id, created_at
) VALUES (
  @id, @beaconId, @authorId, @body, @threadItemId, '2026-01-03T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
'''),
      parameters: {
        'id': BeaconHierarchyTopology.retiredAskThreadMessageId,
        'beaconId': BeaconHierarchyTopology.beaconA,
        'authorId': BeaconHierarchyTopology.aliceId,
        'body': 'Retired ask thread message',
        'threadItemId': BeaconHierarchyTopology.retiredAskItemId,
      },
    );
  }
}

Future<bool> canConnectBeaconHierarchyPostgres() async {
  final target = BeaconHierarchyDisposablePgTarget.fromEnvironment();
  try {
    final connection = await Connection.open(
      target.adminEnv.pgEndpoint,
      settings: target.adminEnv.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } catch (_) {
    return false;
  }
}

Future<({Connection writer, TenturaDb db})> openBeaconHierarchyPgSession(
  BeaconHierarchyDisposablePgTarget target,
) async {
  final writer = await Connection.open(
    target.databaseEnv.pgEndpoint,
    settings: target.databaseEnv.pgEndpointSettings,
  );
  await writer.execute('SET check_function_bodies = false');
  await migrateDbSchema(writer);
  final db = TenturaDb(target.databaseEnv);
  final currentDb = await writer.execute('SELECT current_database()');
  final name = currentDb.first.first as String;
  if (name != target.databaseName) {
    throw StateError(
      'Expected database ${target.databaseName}, connected to $name',
    );
  }
  return (writer: writer, db: db);
}

String beaconHierarchyJson(Map<String, Object?> value) => jsonEncode(value);
