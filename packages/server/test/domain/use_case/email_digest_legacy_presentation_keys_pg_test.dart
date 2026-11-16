@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/notification_identity_repository.dart';
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/data/service/email/file_sink_email_sender.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

const _reader = 'Udlreader';
const _anna = 'Udlanna';
const _roof = 'Bdlroof';
const _readerEmail = 'reader@example.com';
final _now = DateTime.utc(2026, 11, 20, 8);

/// The digest must survive outbox rows whose presentation key the renderer no
/// longer knows: such a row is skipped and marked emailed
/// on its own, and never stops the account's other rows from being sent.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DIGEST_LEGACY_KEYS_TEST_DB',
    defaultNamePrefix: 'tentura_test_digest_legacy_keys',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  late TenturaDb database;
  late Directory sinkDir;
  late Env env;
  late _CountingSender sender;
  late List<LogRecord> logs;
  late StreamSubscription<LogRecord> logSub;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  setUp(() async {
    sinkDir = Directory.systemTemp.createTempSync('digest_legacy_sink_');
    env = Env(
      environment: Environment.test,
      publicOrigin: 'https://t.example',
      unsubscribeSigningSecret: 'digest-legacy-secret',
      emailDebugSinkDir: sinkDir.path,
      emailDigestHour: 8,
      printEnv: false,
    );
    logs = [];
    sender = _CountingSender(FileSinkEmailSender(env));
    logSub = Logger('digest-legacy-test').onRecord.listen(logs.add);
    await writer.execute('''
TRUNCATE public.notification_outbox, public.notification_preference,
  public.user_block, public.beacon, public."user" CASCADE
''');
    for (final (id, name) in [(_reader, 'Reader'), (_anna, 'Anna')]) {
      await writer.execute(
        'INSERT INTO public."user" (id, display_name, public_key) '
        "VALUES ('$id', '$name', 'key-$id')",
      );
    }
    await writer.execute(
      'INSERT INTO public.beacon (id, user_id, title, description, status, '
      'kind, published_at, is_discoverable) '
      "VALUES ('$_roof', '$_reader', 'Fix the roof', '', 0, 0, now(), false)",
    );
    await writer.execute('''
INSERT INTO public.notification_preference (
  account_id, locale, tz_offset_minutes, lock_screen_safe, email_digest,
  email_categories
) VALUES ('$_reader', 'en', 0, false, 'daily',
  ARRAY['asksOfMe', 'unblocksMe', 'coordination', 'connections',
        'ambient', 'postsSharedWithMe'])
''');
  });

  tearDown(() async {
    await logSub.cancel();
    if (sinkDir.existsSync()) sinkDir.deleteSync(recursive: true);
  });

  /// One outbox row as a producer persisted it;
  Future<void> row(
    String id, {
    required String? key,
    required DateTime at,
    String category = 'asksOfMe',
    String kind = 'commitmentEvent',
    String? actor,
    Map<String, Object?> facts = const {},
  }) async {
    await writer.execute(
      Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, source_event_key, destination_kind, target_entity_id,
  presentation_key, presentation_payload, access_policy, beacon_id,
  actor_user_id, created_at
) VALUES (
  @id, @reader, @category, @kind, 'normal', 'STORED-TITLE', 'STORED-BODY',
  '/#/beacon/view/$_roof', @id, @id, 'beacon', '$_roof',
  @key, @payload::jsonb, 'beacon_content', '$_roof', @actor, @at
)
'''),
      parameters: {
        'id': id,
        'reader': _reader,
        'category': category,
        'kind': kind,
        'key': key,
        'payload': jsonEncode({
          'eventType': key ?? 'legacy',
          'beaconId': _roof,
          'targetEntityId': _roof,
          'actorUserId': ?actor,
          if (actor != null) 'actorName': 'Anna',
          ...facts,
        }),
        'actor': actor,
        'at': at,
      },
    );
  }

  Future<void> valid(String id, {DateTime? at, String actor = _anna}) => row(
    id,
    key: 'help_offer_submitted',
    at: at ?? DateTime.utc(2026, 11, 19, 12),
    actor: actor,
    facts: {'excerpt': 'I can bring a ladder'},
  );

  Future<void> legacy(
    String id, {
    String? key = 'room_member_removed',
    DateTime? at,
  }) => row(
    id,
    key: key,
    at: at ?? DateTime.utc(2026, 11, 19, 13),
    category: 'coordination',
  );

  EmailDigestCase digestCase() => EmailDigestCase(
    NotificationPreferenceRepository(database),
    NotificationOutboxRepository(database),
    _Contacts(),
    sender,
    EmailLinkBuilder(env),
    env,
    Logger('digest-legacy-test'),
    identity: NotificationIdentityRepository(database),
  );

  File digestFile() => File(
    '${sinkDir.path}/'
    '${FileSinkEmailSender.sanitizeEmailForFileName(_readerEmail)}.json',
  );

  Future<bool> emailed(String id) async {
    final rows = await writer.execute(
      Sql.named(
        'SELECT emailed_at IS NOT NULL FROM public.notification_outbox '
        'WHERE id = @i',
      ),
      parameters: {'i': id},
    );
    return rows.single.single! as bool;
  }

  bool digestFailureLogged() =>
      logs.any((r) => r.message.contains('[Digest] failed for'));

  String sentText() {
    expect(digestFile().existsSync(), isTrue, reason: 'a digest was sent');
    return (jsonDecode(digestFile().readAsStringSync())
            as Map<String, dynamic>)['text']
        as String;
  }

  test(
    'legacy-key row is marked emailed and the current row is still sent',
    () async {
      await valid('current');
      await legacy('legacy');

      await digestCase().runDue(now: _now);

      expect(sentText(), contains('ladder'));
      expect(sender.digests, 1, reason: 'exactly one digest per account');
      expect(await emailed('current'), isTrue);
      expect(await emailed('legacy'), isTrue);
      expect(digestFailureLogged(), isFalse);
    },
  );

  test(
    'account with only legacy rows gets no digest but is no longer pending',
    () async {
      await legacy('legacy');
      await legacy(
        'legacy2',
        key: 'offer_removed_legacy',
        at: DateTime.utc(2026, 11, 19, 14),
      );

      await digestCase().runDue(now: _now);

      expect(sender.digests, 0);
      expect(digestFile().existsSync(), isFalse);
      expect(await emailed('legacy'), isTrue);
      expect(await emailed('legacy2'), isTrue);
      expect(
        await NotificationOutboxRepository(database).accountsWithPendingEmail(),
        isNot(contains(_reader)),
      );
    },
  );

  // pendingForAccount orders newest first (created_at DESC), so the legacy
  // row (13:00) comes before both valid rows (12:00, 11:00).
  test('legacy row sorting first does not stop later valid rows', () async {
    await legacy('legacy');
    await valid('v1', at: DateTime.utc(2026, 11, 19, 12));
    await valid('v2', at: DateTime.utc(2026, 11, 19, 11));

    await digestCase().runDue(now: _now);

    expect(sentText(), contains('ladder'));
    expect(sender.digests, 1, reason: 'exactly one digest per account');
    for (final id in ['legacy', 'v1', 'v2']) {
      expect(await emailed(id), isTrue, reason: id);
    }
    expect(digestFailureLogged(), isFalse);
  });

  // Rows written before presentation keys existed carry no key. The shipped
  // column is NOT NULL, so this group relaxes it on the disposable database
  // only for its own duration and restores it afterwards.
  group('rows without a presentation key', () {
    setUp(() async {
      await writer.execute(
        'ALTER TABLE public.notification_outbox '
        'ALTER COLUMN presentation_key DROP NOT NULL',
      );
    });

    tearDown(() async {
      await writer.execute('TRUNCATE public.notification_outbox CASCADE');
      await writer.execute(
        'ALTER TABLE public.notification_outbox '
        'ALTER COLUMN presentation_key SET NOT NULL',
      );
    });

    test(
      'NULL-key row is marked emailed and the current row is still sent',
      () async {
        await valid('current');
        await legacy('nokey', key: null);

        await digestCase().runDue(now: _now);

        expect(sentText(), contains('ladder'));
        expect(sender.digests, 1, reason: 'exactly one digest per account');
        expect(await emailed('current'), isTrue);
        expect(await emailed('nokey'), isTrue);
      },
    );

    test('account with only NULL-key rows gets no digest but is no longer '
        'pending', () async {
      await legacy('nokey', key: null);
      await legacy('nokey2', key: null, at: DateTime.utc(2026, 11, 19, 14));

      await digestCase().runDue(now: _now);

      expect(sender.digests, 0);
      expect(await emailed('nokey'), isTrue);
      expect(await emailed('nokey2'), isTrue);
      expect(
        await NotificationOutboxRepository(database).accountsWithPendingEmail(),
        isNot(contains(_reader)),
      );
    });
  });

  test('rows hidden by a block stay pending next to a legacy row', () async {
    await writer.execute(
      'INSERT INTO public."user" (id, display_name, public_key) '
      "VALUES ('Udlblocked', 'Blocked', 'key-blocked')",
    );
    await writer.execute(
      'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
      "VALUES ('$_reader', 'Udlblocked', '$_reader')",
    );
    await valid('current');
    await row(
      'hidden',
      key: 'help_offer_submitted',
      at: DateTime.utc(2026, 11, 19, 10),
      actor: 'Udlblocked',
      facts: {'excerpt': 'hidden offer'},
    );
    await legacy('legacy');

    await digestCase().runDue(now: _now);

    expect(sentText(), contains('ladder'));
    expect(sender.digests, 1);
    expect(await emailed('legacy'), isTrue);
    expect(await emailed('current'), isTrue);
    expect(await emailed('hidden'), isFalse);
  });

  test('expired post warning stays pending next to a legacy row', () async {
    await valid('current');
    await row(
      'expired',
      key: 'post_expiring_soon',
      kind: 'postExpiringSoon',
      category: 'coordination',
      at: DateTime.utc(2026, 11, 19, 7),
      facts: {'expiresAt': '2026-11-20T07:00:00.000Z'},
    );
    await legacy('legacy');

    await digestCase().runDue(now: _now);

    expect(sentText(), contains('ladder'));
    expect(sender.digests, 1);
    expect(await emailed('legacy'), isTrue);
    expect(await emailed('current'), isTrue);
    expect(await emailed('expired'), isFalse);
  });
}

final class _Contacts implements VerifiedContactRepositoryPort {
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async =>
      accountId == _reader ? _readerEmail : null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

/// Delegates to the file sink and counts the digests handed to it.
final class _CountingSender implements EmailSenderPort {
  _CountingSender(this._inner);

  final FileSinkEmailSender _inner;
  int digests = 0;

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) {
    digests++;
    return _inner.sendDigestEmail(
      to: to,
      locale: locale,
      content: content,
      listUnsubscribeUrl: listUnsubscribeUrl,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
