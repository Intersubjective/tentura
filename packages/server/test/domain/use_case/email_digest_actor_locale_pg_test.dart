@Tags(['pg'])
library;

import 'dart:math';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
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
import '../../support/fake_user_block_repository.dart';

const _reader = 'UactorDigestReader';
const _beacon = 'BactorDigest';
const _actors = [('UactorDigestAnna', 'Anna'), ('UactorDigestBoris', 'Борис')];

// Produce English receipts through the real intent/dispatch path, then exercise
// the preference/outbox repositories, digest use case and email rendering.
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
            // AttentionIntentCase.helpOfferSubmitted constructs a
            // BeaconNotificationIntent(kind: NotificationKind.commitmentEvent)
            // and dispatches it as AttentionEventType.helpOfferSubmitted.
            // commitmentEvent is the digest/outbox kind, not a separate
            // producer event; this exercises that mapping through dispatch.
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
              '{actor}',
              '{actor} asks if you can help',
              '{actor}',
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
        final behavior = switch (kind) {
          'commitmentEvent' => 'help offers',
          'roomMention' => 'discussion mentions',
          'batonAsked' => 'requests to take a task',
          'roomAccess' => 'accepted help offers',
          _ => throw StateError('Missing test description for $kind'),
        };
        test('$behavior use Russian in HTML and plain text', () async {
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
            final env = target.databaseEnv;
            final guard = FakeBeaconAccessGuard();
            final intents = AttentionIntentCase(
              BeaconRoomNotificationContextRepository(
                BeaconRoomRepository(database),
                database,
                HelpOfferRepository(database),
                CommitmentRepository(database),
              ),
              UserRepository(
                env,
                database,
                _UnusedGenealogy(),
                InviteSeedPromptRepositoryMock(),
              ),
              guard,
              FakeUserBlockRepository(),
            );
            final attention = TransactionalAttentionCase(
              MutatingUnitOfWork(database),
              AttentionDispatchRepository(database, Logger('digest-producer')),
            );
            // Fresh, unrelated names on every pass make fixed fixture-name
            // substitutions fail. Names enter the system via actor profiles;
            // tests never insert notification rows or presentation payloads.
            final actors = <(String, String)>[];
            for (final (actorId, prefix) in _actors) {
              final name = '$prefix №${Random.secure().nextInt(1 << 32)}';
              actors.add((actorId, name));
              await session.writer.execute(
                Sql.named(
                  'UPDATE public."user" SET display_name = @name WHERE id = @id',
                ),
                parameters: {'id': actorId, 'name': name},
              );
              final messageId = 'M$actorId';
              await session.writer.execute(
                Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@id, '$_beacon', @actor, 'Can you help?')
ON CONFLICT (id) DO NOTHING
'''),
                parameters: {'id': messageId, 'actor': actorId},
              );
              final source = '$eventType-$locale-$actorId';
              final AttentionDispatchIntent intent = switch (eventType) {
                'helpOfferSubmitted' => await intents.helpOfferSubmitted(
                  beaconId: _beacon,
                  helpOffererId: actorId,
                  authorId: _reader,
                  sourceEventKey: source,
                ),
                'roomMessagePosted' => await intents.roomMentioned(
                  beaconId: _beacon,
                  messageId: messageId,
                  actorUserId: actorId,
                  recipientUserIds: {_reader},
                  excerpt: '',
                  sourceEventKey: source,
                ),
                'batonAsked' => await intents.batonAsked(
                  beaconId: _beacon,
                  messageId: messageId,
                  actorUserId: actorId,
                  recipientId: _reader,
                  excerpt: '',
                  sourceEventKey: source,
                ),
                'offerAccepted' => await intents.offerAccepted(
                  receiverId: _reader,
                  beaconId: _beacon,
                  actorUserId: actorId,
                  sourceEventKey: source,
                ),
                _ => throw StateError('Unsupported event $eventType'),
              };
              await attention.run(
                actorUserId: actorId,
                intent: intent,
                mutation: () async {},
              );
            }
            final outbox = NotificationOutboxRepository(database);
            final pending = await outbox.pendingForAccount(_reader);
            expect(pending, hasLength(actors.length));
            for (final receipt in pending) {
              final name = actors
                  .singleWhere((a) => a.$1 == receipt.actorUserId)
                  .$2;
              expect(receipt.kind.name, kind);
              // These values come from AttentionPolicy, not the test fixture.
              expect(receipt.presentationKey, switch (eventType) {
                'helpOfferSubmitted' => 'help_offer_submitted',
                'roomMessagePosted' => 'room_message_posted',
                'batonAsked' => 'baton_asked',
                'offerAccepted' => 'offer_accepted',
                _ => throw StateError('Unsupported event $eventType'),
              });
              expect(receipt.title, named(englishTitle, name));
              expect(receipt.body, named(englishBody, name));
              // Actor-name transport is deliberately unconstrained: delivery
              // may resolve the profile or use a producer-supplied payload.
              // The observable requirement is correctly named localized copy.
            }

            final sender = _RenderedDigestSender();
            await EmailDigestCase(
              NotificationPreferenceRepository(database),
              outbox,
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
            // Assert the notification fields at the public email delivery
            // boundary. Title and body are separate values, irrespective of
            // the HTML markup the template chooses to put around them.
            final expected = [
              for (final (actorId, name) in actors)
                (
                  title: named(locale == 'ru' ? ruTitle : englishTitle, name),
                  body: named(locale == 'ru' ? ruBody : englishBody, name),
                  url: EmailLinkBuilder(env).absolute(
                    pending
                        .singleWhere((i) => i.actorUserId == actorId)
                        .actionUrl,
                  ),
                ),
            ];
            expect(
              [
                for (final section in delivered.content.sections)
                  for (final item in section.items)
                    (title: item.title, body: item.body, url: item.url),
              ],
              unorderedEquals(expected),
              reason: '$locale notification copy delivered to the recipient',
            );
            // EmailTemplateRenderer.renderDigest defines each plain-text row
            // as "- <title> — <body>\n  <url>" and each HTML row as an <li>
            // containing a title link followed by " — <body>". Assert those
            // distinct rendered fields rather than a contiguous title/body.
            final htmlRows = RegExp('<li>(.*?)</li>', dotAll: true)
                .allMatches(delivered.rendered.html)
                .map((m) => m.group(1)!)
                .toList();
            expect(htmlRows, hasLength(expected.length));
            for (final item in expected) {
              final row = htmlRows.singleWhere((r) => r.contains(item.title));
              expect(row, contains('>${item.title}</a>'));
              expect(row, endsWith(' — ${item.body}'));
              expect(
                delivered.rendered.text,
                contains('- ${item.title} — ${item.body}\n  ${item.url}'),
              );
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
  final messages =
      <
        ({
          String to,
          String locale,
          EmailDigestContent content,
          RenderedEmail rendered,
        })
      >[];

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
      content: content,
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

class _UnusedGenealogy implements InviteGenealogyRepositoryPort {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
