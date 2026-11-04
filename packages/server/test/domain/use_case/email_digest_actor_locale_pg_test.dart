@Tags(['pg'])
library;

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';

const _reader = 'UactorDigestReader';
const _beacon = 'BactorDigest';
const _actors = [('UactorDigestAnna', 'Anna'), ('UactorDigestBoris', 'Борис')];

// Persist English receipts independently of the reader, then exercise the real
// preference/outbox repositories, digest use case and both email MIME parts.
// Only contact lookup, SMTP and access authorization are substituted, as in
// email_digest_recipient_locale_pg_test.dart.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DIGEST_ACTOR_LOCALE_TEST_DB',
    defaultNamePrefix: 'tentura_test_digest_actor_locale',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb database;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    database = openDisposablePgDatabase(target);
    for (final (id, name) in [(_reader, 'Reader'), ..._actors]) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @name, @id)
'''),
        parameters: {'id': id, 'name': name},
      );
    }
    await session.writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('$_beacon', '$_reader', 'Request', 'Description', 0)
''');
  });
  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  group(
    'Russian digests retain actor names and translate notification copy',
    () {
      for (final (kind, eventType, englishTitle, englishBody, ruTitle, ruBody)
          in const [
            (
              'commitmentEvent',
              'helpOfferSubmitted',
              '{actor}',
              '{actor} offered help',
              '{actor}',
              '{actor} предложил(а) помощь',
            ),
            (
              'roomMention',
              'roomMessagePosted',
              '{actor}',
              '{actor} mentioned you',
              '{actor}',
              '{actor} упомянул(а) вас',
            ),
            (
              'batonAsked',
              'batonAsked',
              '{actor} asks if you can help',
              '{actor} asks if you can help',
              '{actor} спрашивает, сможете ли вы помочь',
              '{actor} спрашивает, сможете ли вы помочь',
            ),
            (
              'roomAccess',
              'offerAccepted',
              '{actor} accepted your offer',
              'Your offer was accepted',
              '{actor} принял(а) ваше предложение',
              'Ваше предложение принято',
            ),
          ]) {
        test('$eventType rows use Russian in HTML and plain text', () async {
          String named(String template, String name) =>
              template.replaceAll('{actor}', name);

          // The same stored English copy must work for both recipient locales.
          // Reset receipts between sends so the cadence watermark cannot hide a
          // localization failure behind a skipped delivery.
          for (final locale in ['en', 'ru']) {
            await session.writer.execute(
              'DELETE FROM public.notification_outbox',
            );
            await session.writer.execute(
              Sql.named('''
INSERT INTO public.notification_preference (
  account_id, locale, email_categories, email_digest
) VALUES (
  '$_reader', @locale, ARRAY['asksOfMe', 'coordination'], 'daily'
)
ON CONFLICT (account_id) DO UPDATE SET locale = EXCLUDED.locale
'''),
              parameters: {'locale': locale},
            );
            for (final (actorId, name) in _actors) {
              await session.writer.execute(
                Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, source_event_key, destination_kind, presentation_key,
  presentation_payload, access_policy, beacon_id, target_entity_id, actor_user_id
) VALUES (
  gen_random_uuid()::text, '$_reader', @category, @kind, 'normal',
  @title, @body, @url, @actor, @actor, 'beacon', @eventType,
  @payload::jsonb, 'beacon_content', '$_beacon', '$_beacon', @actor
)
'''),
                parameters: {
                  'category': kind == 'roomAccess'
                      ? 'asksOfMe'
                      : 'coordination',
                  'kind': kind,
                  'title': named(englishTitle, name),
                  'body': named(englishBody, name),
                  'url': '/#/beacon/$_beacon?is_deep_link=true',
                  'actor': actorId,
                  'eventType': eventType,
                  // These two producer events already carry the name in their
                  // presentation payload; the others have the actor user id.
                  'payload': jsonEncode({
                    'eventType': eventType,
                    'excerpt': '',
                    if (eventType == 'helpOfferSubmitted' ||
                        eventType == 'offerAccepted')
                      'actorName': name,
                  }),
                },
              );
            }

            final sender = _RenderedDigestSender();
            final env = target.databaseEnv;
            await EmailDigestCase(
              NotificationPreferenceRepository(database),
              NotificationOutboxRepository(database),
              _Contacts(),
              sender,
              EmailLinkBuilder(env),
              env,
              Logger('digest-actor-locale-test'),
              FakeBeaconAccessGuard(),
            ).runDue(now: DateTime.utc(2026, 11, 4, env.emailDigestHour));

            expect(sender.messages, hasLength(1));
            final delivered = sender.messages.single;
            expect(delivered.to, 'reader@example.com');
            expect(delivered.locale, locale);
            for (final (format, part) in [
              ('HTML', delivered.rendered.html),
              ('plain text', delivered.rendered.text),
            ]) {
              for (final (_, name) in _actors) {
                expect(
                  part,
                  contains(
                    named(locale == 'ru' ? ruTitle : englishTitle, name),
                  ),
                  reason: '$locale $format title for $name',
                );
                expect(
                  part,
                  contains(named(locale == 'ru' ? ruBody : englishBody, name)),
                  reason: '$locale $format body for $name',
                );
                if (locale == 'ru') {
                  if (ruTitle != englishTitle) {
                    expect(part, isNot(contains(named(englishTitle, name))));
                  }
                  expect(part, isNot(contains(named(englishBody, name))));
                }
              }
              expect(part, isNot(contains('Someone')));
              expect(part, isNot(contains('Кто-то')));
              expect(part, contains('/#/beacon/$_beacon?is_deep_link=true'));
            }
          }
        });
      }
    },
  );
}

class _Contacts implements VerifiedContactRepositoryPort {
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async =>
      'reader@example.com';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _RenderedDigestSender implements EmailSenderPort {
  final messages = <({String to, String locale, RenderedEmail rendered})>[];

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    messages.add((
      to: to,
      locale: locale,
      rendered: const EmailTemplateRenderer().renderDigest(
        content: content,
        locale: locale,
      ),
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
