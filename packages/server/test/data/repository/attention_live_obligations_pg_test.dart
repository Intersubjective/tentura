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
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_LIVE_OBLIGATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_live_obl',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('liveObligationBeacons', () {
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
        (_viewerId, 'live-obligation-viewer-key'),
        (_otherId, 'live-obligation-other-key'),
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
VALUES
  (@contentId, @viewerId, 'Readable', 'Readable request', 0),
  (@hiddenId, @otherId, 'Hidden', 'Hidden request', 0)
'''),
        parameters: {
          'contentId': _contentBeaconId,
          'hiddenId': _hiddenBeaconId,
          'viewerId': _viewerId,
          'otherId': _otherId,
        },
      );
    });

    tearDownAll(() async {
      await writer.close();
      await target.drop();
    });

    test('includes an authorized live obligation beacon id', () async {
      await _insertLiveObligationReceipt(
        writer,
        id: 'Nlive01',
        beaconId: _contentBeaconId,
      );

      expect(
        await query.liveObligationBeacons(accountId: _viewerId),
        {_contentBeaconId},
      );
    });

    test('excludes a settled obligation', () async {
      await _insertLiveObligationReceipt(
        writer,
        id: 'Nsettled01',
        beaconId: _contentBeaconId,
      );
      await writer.execute('''
UPDATE public.notification_outbox
SET
  settlement_kind = 'resolved',
  settled_at = now(),
  settled_by_user_id = '$_viewerId'
WHERE id = 'Nsettled01'
''');

      expect(
        await query.liveObligationBeacons(accountId: _viewerId),
        isEmpty,
      );
    });

    test('includes a seen-but-unsettled obligation', () async {
      await _insertLiveObligationReceipt(
        writer,
        id: 'Nseen01',
        beaconId: _contentBeaconId,
        seenAt: '2026-07-17T12:00:00Z',
      );

      expect(
        await query.liveObligationBeacons(accountId: _viewerId),
        {_contentBeaconId},
      );
    });

    test('excludes a receipt the viewer is not authorized for', () async {
      await _insertLiveObligationReceipt(
        writer,
        id: 'Nhidden01',
        beaconId: _hiddenBeaconId,
        accessPolicy: 'beacon_content',
        destinationKind: 'beacon',
        presentationKey: 'request_status_changed',
      );

      expect(
        await query.liveObligationBeacons(accountId: _viewerId),
        isEmpty,
      );
    });

    test('deduplicates two live obligations on one Beacon', () async {
      await _insertLiveObligationReceipt(
        writer,
        id: 'Ndup01',
        beaconId: _contentBeaconId,
        threadKey: 'v1|needsMe|item-1|$_viewerId',
      );
      await _insertLiveObligationReceipt(
        writer,
        id: 'Ndup02',
        beaconId: _contentBeaconId,
        threadKey: 'v1|needsMe|item-2|$_viewerId',
      );

      expect(
        await query.liveObligationBeacons(accountId: _viewerId),
        {_contentBeaconId},
      );
    });
  }, skip: skipReason);
}

const _viewerId = 'Uliveobl01';
const _otherId = 'Uliveobl02';
const _contentBeaconId = 'Bliveoblcont';
const _hiddenBeaconId = 'Bliveoblhide';

Future<void> _insertLiveObligationReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  String accessPolicy = 'beacon_content',
  String destinationKind = 'beacon',
  String presentationKey = 'request_status_changed',
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
  @destinationKind, @presentationKey, '{"eventType":"fixture"}'::jsonb,
  'standard', @accessPolicy,
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
    'destinationKind': destinationKind,
    'presentationKey': presentationKey,
    'accessPolicy': accessPolicy,
    'threadKey': threadKey ?? 'v1|needsMe|$id|$_viewerId',
  },
);

