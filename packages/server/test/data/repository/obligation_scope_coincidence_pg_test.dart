@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('needsYou scope/count coincidence (one attentionFeed snapshot)', () {
    late Connection writer;
    late AttentionRepository query;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      final database = TenturaDb(target.databaseEnv);
      query = AttentionRepository(database);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
      for (final (id, key) in const [
        (_viewerId, 'obligation-scope-viewer-key'),
      ]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': id, 'key': key},
        );
      }
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@contentId, @viewerId, 'Readable', 'Readable request', 0)
'''),
        parameters: {
          'contentId': _contentBeaconId,
          'viewerId': _viewerId,
        },
      );
    });

    tearDownAll(() async {
      await writer.close();
      await target.drop();
    });

    test('empty obligations: scope and count agree at zero', () async {
      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.needsYou,
      );
      _expectScopeCountCoincidence(feed);
      expect(feed.summary.needsYouTotal, 0);
    });

    test(
      'two live receipts on one Beacon: count is two and scope lists both',
      () async {
        await _insertLiveObligationReceipt(
          writer,
          id: 'Nscope01',
          beaconId: _contentBeaconId,
          threadKey: 'v1|needsMe|item-1|$_viewerId',
        );
        await _insertLiveObligationReceipt(
          writer,
          id: 'Nscope02',
          beaconId: _contentBeaconId,
          threadKey: 'v1|needsMe|item-2|$_viewerId',
        );

        final feed = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.needsYou,
        );
        _expectScopeCountCoincidence(feed);
        expect(feed.summary.needsYouTotal, 2);
        expect(
          feed.page.items.map((item) => item.id).toSet(),
          {'Nscope01', 'Nscope02'},
        );
      },
    );

    test(
      'settling one of two leaves one obligation in scope and count',
      () async {
        await _insertLiveObligationReceipt(
          writer,
          id: 'Nscope03',
          beaconId: _contentBeaconId,
          threadKey: 'v1|needsMe|item-3|$_viewerId',
        );
        await _insertLiveObligationReceipt(
          writer,
          id: 'Nscope04',
          beaconId: _contentBeaconId,
          threadKey: 'v1|needsMe|item-4|$_viewerId',
        );
        await writer.execute('''
UPDATE public.notification_outbox
SET
  settlement_kind = 'resolved',
  settled_at = now(),
  settled_by_user_id = '$_viewerId'
WHERE id = 'Nscope03'
''');

        final feed = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.needsYou,
        );
        _expectScopeCountCoincidence(feed);
        expect(feed.summary.needsYouTotal, 1);
        expect(feed.page.items.single.id, 'Nscope04');
      },
    );

    test(
      'seen-but-unsettled obligations stay in scope and count',
      () async {
        await _insertLiveObligationReceipt(
          writer,
          id: 'Nscope05',
          beaconId: _contentBeaconId,
          seenAt: '2026-07-17T12:00:00Z',
        );

        final feed = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.needsYou,
        );
        _expectScopeCountCoincidence(feed);
        expect(feed.summary.needsYouTotal, 1);
      },
    );

    test(
      'authorization loss removes scope and count without terminal settlement',
      () async {
        await _insertLiveObligationReceipt(
          writer,
          id: 'Nscope06',
          beaconId: _contentBeaconId,
        );

        final before = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.needsYou,
        );
        _expectScopeCountCoincidence(before);
        expect(before.summary.needsYouTotal, 1);

        await writer.execute('''
UPDATE public.beacon
SET status = 2
WHERE id = '$_contentBeaconId'
''');

        final after = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.needsYou,
        );
        _expectScopeCountCoincidence(after);
        expect(after.summary.needsYouTotal, 0);

        final settlement = await writer.execute(
          Sql.named('''
SELECT settlement_kind, settled_at
FROM public.notification_outbox
WHERE id = @id
'''),
          parameters: {'id': 'Nscope06'},
        );
        expect(settlement.first[0], isNull);
        expect(settlement.first[1], isNull);
      },
    );
  }, skip: skipReason);
}

void _expectScopeCountCoincidence(AttentionFeed feed) {
  expect(
    feed.summary.needsYouTotal,
    feed.page.items.length,
    reason: 'needsYouTotal must match needsYou page size from one snapshot',
  );
  for (final receipt in feed.page.items) {
    expect(receipt.requiresAction, isTrue);
    expect(receipt.settlementKind, isNull);
  }
}

const _viewerId = 'Uoblscope01';
const _contentBeaconId = 'Boblscopecont';

Future<void> _insertLiveObligationReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  String? seenAt,
  String? threadKey,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  @id, @accountId, 'asksOfMe', 'needsMe', 'normal',
  'Obligation', 'Obligation body', '/attention', @dedupKey,
  '2026-07-16T12:00:00Z'::timestamptz,
  CAST(@seenAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  true, @threadKey
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'seenAt': seenAt,
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'threadKey': threadKey ?? 'v1|needsMe|$id|$_viewerId',
  },
);

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
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
        Platform.environment['TENTURA_OBLIGATION_SCOPE_TEST_DB'] ??
        'tentura_test_obl_scope_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_OBLIGATION_SCOPE_TEST_DB',
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
