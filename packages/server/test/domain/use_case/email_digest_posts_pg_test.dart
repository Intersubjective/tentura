@Tags(['pg'])
library;

import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/notification_outbox_repository.dart';
import 'package:tentura_server/data/repository/notification_identity_repository.dart';
import 'package:tentura_server/data/repository/notification_preference_repository.dart';
import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/notification/beacon_notification_copy_builder.dart';
import 'package:tentura_server/domain/notification/notification_text.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

const _reader = 'Upostdigestreader';
const _alice = 'Upostdigestalice';
const _bob = 'Upostdigestbob';
const _shared = 'Bdigestshared';
const _other = 'Bdigestother';
const _own = 'Bdigestown';
const _request = 'Bdigestrequest';
final _postBody =
    'A neighbourhood story ${List.filled(30, 'with more words').join(' ')} END_OF_POST';

// Persist the data a recipient receives, then run the real outbox/preference
// repositories, digest use case and HTML/text renderer. Only SMTP/contact
// lookup and authorization are substituted, as in the locale digest pg test.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DIGEST_POSTS_TEST_DB',
    defaultNamePrefix: 'tentura_test_digest_posts',
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
    await session.writer.execute('''
INSERT INTO public."user" (id, display_name, public_key) VALUES
('$_reader', 'Reader', 'post-digest-reader-key'),
('$_alice', 'Alice', 'post-digest-alice-key'),
('$_bob', 'Bob', 'post-digest-bob-key')
''');
    for (final (id, author, kind) in [
      (_shared, _alice, 1),
      (_other, _bob, 1),
      (_own, _reader, 1),
      (_request, _alice, 0),
    ]) {
      await session.writer.execute(
        Sql.named('''
INSERT INTO public.beacon
(id, user_id, title, description, status, kind, forward_policy, is_discoverable, published_at)
VALUES (@id, @author, @title, '', 0, @kind, 1, false, now())
'''),
        parameters: {
          'id': id,
          'author': author,
          'kind': kind,
          'title': kind == 0 ? 'Request for help' : '',
        },
      );
      if (kind == 1) {
        await session.writer.execute(
          Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@message, @beacon, @author, @body)
'''),
          parameters: {
            'message': 'M$id',
            'beacon': id,
            'author': author,
            'body': _postBody,
          },
        );
        await session.writer.execute(
          Sql.named(
            'UPDATE public.beacon SET post_root_message_id = @message WHERE id = @id',
          ),
          parameters: {'message': 'M$id', 'id': id},
        );
      }
    }
    await session.writer.execute('''
INSERT INTO public.beacon_forward_edge
(id, beacon_id, sender_id, recipient_id, note) VALUES
('Fdigestalice', '$_shared', '$_alice', '$_reader', 'Read this before Saturday'),
('Fdigestbob', '$_shared', '$_bob', '$_reader', 'This made me think of you'),
('Fdigestother', '$_other', '$_bob', '$_reader', ''),
('Fdigestrequest', '$_request', '$_alice', '$_reader', 'Request-only note')
''');
  });
  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });
  setUp(() async {
    await session.writer.execute('DELETE FROM public.notification_outbox');
    await session.writer.execute(
      Sql.named('UPDATE public.beacon_room_message SET body = @body'),
      parameters: {'body': _postBody},
    );
  });

  Future<void> receipt({
    required String id,
    required String beacon,
    String kind = 'newRelay',
    String actor = _alice,
    String name = 'Alice',
    String note = '',
  }) async {
    final event = kind == 'newRelay' ? 'relayReceived' : kind;
    final presentationKey = event.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '_${m.group(0)!.toLowerCase()}',
    );
    final copy = const BeaconNotificationCopyBuilder().build(
      intent: BeaconNotificationIntent(
        kind: NotificationKind.values.byName(kind),
        priority: NotificationPriority.normal,
        beaconId: beacon,
        actorUserId: actor,
        beaconKind: beacon == _request ? BeaconKind.request : BeaconKind.post,
        bodyExcerpt: note,
      ),
      actorDisplayName: name,
    );
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.notification_outbox
(id, account_id, category, kind, priority, title, body, action_url,
 dedup_key, source_event_key, destination_kind, target_entity_id,
 presentation_key, presentation_payload, access_policy, beacon_id, actor_user_id)
VALUES (@id, @reader, 'coordination', @kind, 'normal', @name, @body, @url,
 @id, @id, 'beacon', @beacon, @event, @payload::jsonb, 'beacon_content', @beacon, @actor)
'''),
      parameters: {
        'id': id,
        'reader': _reader,
        'kind': kind,
        'name': copy.title,
        'body': copy.body,
        'url': copy.actionUrl,
        'beacon': beacon,
        'actor': actor,
        'event': presentationKey,
        'payload': jsonEncode({
          'eventType': event,
          'personal': true,
          'beaconId': beacon,
          'targetEntityId': beacon,
          'actorUserId': actor,
          'actorName': name,
          'excerpt': note,
        }),
      },
    );
  }

  Future<RenderedEmail> deliver(String locale) async {
    await session.writer.execute(
      Sql.named('''
INSERT INTO public.notification_preference
(account_id, locale, email_categories, email_digest)
VALUES (@reader, @locale, ARRAY['asksOfMe', 'connections', 'coordination', 'postsSharedWithMe'], 'daily')
ON CONFLICT (account_id) DO UPDATE SET locale = EXCLUDED.locale
'''),
      parameters: {'reader': _reader, 'locale': locale},
    );
    final sender = _DeliveredDigest();
    final env = Env(
      environment: Environment.test,
      publicOrigin: 'https://tentura.example',
      unsubscribeSigningSecret: 'digest-test-secret',
      printEnv: false,
    );
    await EmailDigestCase(
      NotificationPreferenceRepository(database),
      NotificationOutboxRepository(database),
      _Contacts(),
      sender,
      EmailLinkBuilder(env),
      env,
      Logger('post-digest-test'),
      identity: NotificationIdentityRepository(database),
    ).runDue(now: DateTime.now().toUtc().copyWith(hour: env.emailDigestHour));
    expect(
      sender.messages,
      hasLength(1),
      reason: 'A due recipient receives one digest',
    );
    expect(sender.recipient, 'reader@example.com');
    expect(sender.locale, locale);
    return sender.messages.single;
  }

  /// The Post group heading (spec §4.1): `Post: {root text ≤ 40}`.
  String postLabel(String locale, String body) =>
      '${locale == 'ru' ? 'Пост' : 'Post'}: '
      '${NotificationText.truncate(body, 40)}';

  String shared(String locale, String name) => locale == 'ru'
      ? '$name делится с вами постом'
      : '$name shared a post with you';

  /// The HTML of each section by heading.
  Map<String, String> sectionsOf(String html) => {
    for (final part in html.split('<h3>').skip(1))
      part.substring(0, part.indexOf('</h3>')): part,
  };

  group('Daily digest Post sections', () {
    for (final locale in ['en', 'ru']) {
      test(
        '$locale names the Post by its label when a share has no note',
        () async {
          // The real share edge has no note, not merely an empty receipt field.
          await receipt(
            id: 'no-note',
            beacon: _other,
            actor: _bob,
            name: 'Bob',
          );
          final email = await deliver(locale);
          expect(
            email.text,
            contains(
              '${postLabel(locale, _postBody)}\n'
              '  https://tentura.example/#/post/view/$_other'
              '?is_deep_link=true\n'
              '- ${shared(locale, 'Bob')}\n',
            ),
          );
          expect(email.html, contains('<li>${shared(locale, 'Bob')}</li>'));
          for (final part in [email.html, email.text]) {
            expect(part, isNot(contains(_postBody.substring(0, 41))));
          }
        },
      );

      for (final length in [39, 40, 41]) {
        test(
          '$locale keeps short Post text and shortens it at the 40 grapheme '
          'boundary for length $length',
          () async {
            final body = '${List.filled(length - 1, 'x').join()}Z';
            await session.writer.execute(
              Sql.named(
                'UPDATE public.beacon_room_message SET body = @body WHERE id = @id',
              ),
              parameters: {'body': body, 'id': 'M$_other'},
            );
            await receipt(
              id: 'boundary',
              beacon: _other,
              actor: _bob,
              name: 'Bob',
            );
            final email = await deliver(locale);
            final expected = length <= 40 ? body : '${body.substring(0, 39)}…';
            final prefix = locale == 'ru' ? 'Пост' : 'Post';
            expect(email.text, contains('$prefix: $expected\n'));
            if (length > 40) {
              for (final part in [email.html, email.text]) {
                expect(part, isNot(contains(body)));
              }
            }
          },
        );
      }

      test(
        '$locale delivers persisted shares through production attention dispatch with the correct Post text and note ownership',
        () async {
          final persistedBody =
              'The actual shared Post ${List.filled(25, 'from the root message').join(' ')}';
          await session.writer.execute(
            Sql.named(
              'UPDATE public.beacon_room_message SET body = @body WHERE id = @id',
            ),
            parameters: {'body': persistedBody, 'id': 'M$_shared'},
          );
          // Other Posts retain a different body, so a wrong Post/root lookup
          // cannot accidentally produce the expected excerpt.
          final env = target.databaseEnv;
          final guard = FakeBeaconAccessGuard();
          final users = UserRepository(
            env,
            database,
            _UnusedGenealogy(),
            InviteSeedPromptRepositoryMock(),
          );
          final intents = AttentionIntentCase(
            BeaconRoomNotificationContextRepository(
              BeaconRoomRepository(database),
              database,
              HelpOfferRepository(database),
              CommitmentRepository(database),
            ),
            users,
            guard,
            FakeUserBlockRepository(),
          );
          final attention = TransactionalAttentionCase(
            MutatingUnitOfWork(database),
            AttentionDispatchRepository(database, Logger('persisted-digest')),
          );
          final edges = ForwardEdgeRepository(database);
          for (final id in ['Fdigestalice', 'Fdigestbob']) {
            final edge = await edges.fetchById(id);
            expect(edge, isNotNull);
            final intent = await intents.relayReceived(
              beaconId: edge!.beaconId,
              senderId: edge.senderId,
              beaconAuthorId: _alice,
              recipientIds: [edge.recipientId],
              sourceEventKey: 'digest-$locale-$id',
              beaconKind: BeaconKind.post,
              noteForRecipient: (_) => edge.note,
            );
            await attention.run(
              actorUserId: edge.senderId,
              intent: intent,
              mutation: () async {},
            );
          }
          // No notification rows or presentation payloads were fabricated here.
          final pending = await NotificationOutboxRepository(
            database,
          ).pendingForAccount(_reader);
          expect(pending, hasLength(2));
          final email = await deliver(locale);
          final section = sectionsOf(email.html).values.single;
          expect('/post/view/$_shared'.allMatches(section), hasLength(1));
          expect(
            section,
            isNot(matches(RegExp('/(?:post|beacon)/view/$_other'))),
          );
          expect(section, contains(postLabel(locale, persistedBody)));
          for (final part in [section, email.text]) {
            expect(part, isNot(contains(postLabel(locale, _postBody))));
            expect(
              part,
              contains('${shared(locale, 'Alice')}: Read this before Saturday'),
            );
            expect(
              part,
              contains('${shared(locale, 'Bob')}: This made me think of you'),
            );
          }
        },
      );

      test(
        '$locale separates shared Posts, replies and expiry from Request forwards',
        () async {
          // Deliberately enqueue in a different order from the section order.
          await receipt(id: 'expiry', beacon: _own, kind: 'postExpiringSoon');
          await receipt(
            id: 'request',
            beacon: _request,
            note: 'Request-only note',
          );
          await receipt(id: 'reply', beacon: _own, kind: 'postFirstResponse');
          await receipt(id: 'share', beacon: _shared);
          final email = await deliver(locale);
          final postHeadings = locale == 'ru'
              ? [
                  'Вам переслали посты',
                  'Ответы на ваши посты',
                  'Скоро истекают',
                ]
              : [
                  'Posts shared with you',
                  'Replies to your posts',
                  'Expiring soon',
                ];
          final headings = RegExp(
            '<h3>(.*?)</h3>',
          ).allMatches(email.html).map((m) => m.group(1)!).toList();
          expect(headings.where(postHeadings.contains).toList(), postHeadings);
          for (final part in [email.html, email.text]) {
            var previous = -1;
            for (final heading in postHeadings) {
              final at = part.indexOf(heading);
              expect(
                at,
                greaterThan(previous),
                reason: 'Post sections follow the specified order',
              );
              previous = at;
            }
          }
          final sections = sectionsOf(email.html);
          for (final (heading, beacon) in [
            (postHeadings[0], _shared),
            (postHeadings[1], _own),
            (postHeadings[2], _own),
          ]) {
            final section = sections[heading]!;
            expect('/post/view/$beacon'.allMatches(section), hasLength(1));
            expect(section, isNot(contains('/beacon/view/$_request')));
            expect(section, isNot(contains('Request-only note')));
          }
          final requestHeading = locale == 'ru'
              ? 'Изменилось, пока вас не было'
              : 'Moved while you were away';
          final requestSection = sections[requestHeading]!;
          expect(
            '/beacon/view/$_request'.allMatches(requestSection),
            hasLength(1),
          );
          expect(requestSection, contains('Request for help'));
          expect(requestSection, contains('Request-only note'));
          expect(
            requestSection,
            isNot(matches(RegExp('/(?:post|beacon)/view/$_shared'))),
          );
          expect(
            requestSection,
            isNot(matches(RegExp('/(?:post|beacon)/view/$_own'))),
          );
          final textSections = email.text.split('\n\n');
          final requestText = textSections.singleWhere(
            (section) => section.startsWith('$requestHeading\n'),
          );
          expect(requestText, contains('/beacon/view/$_request'));
          expect(requestText, contains('Request-only note'));
          for (final part in [email.html, email.text]) {
            expect(
              part,
              contains('https://tentura.example/#/beacon/view/$_request'),
            );
            for (final post in [_shared, _own]) {
              expect(
                part,
                contains('https://tentura.example/#/post/view/$post'),
              );
              expect(part, isNot(contains('/beacon/view/$post')));
            }
          }
          expect(
            requestText,
            isNot(matches(RegExp('/(?:post|beacon)/view/$_shared'))),
          );
          expect(
            requestText,
            isNot(matches(RegExp('/(?:post|beacon)/view/$_own'))),
          );
        },
      );

      test(
        '$locale merges shares by Post while keeping each note with its sender',
        () async {
          await receipt(
            id: 'alice-share',
            beacon: _shared,
            note: 'Read this before Saturday',
          );
          await receipt(
            id: 'bob-share',
            beacon: _shared,
            actor: _bob,
            name: 'Bob',
            note: 'This made me think of you',
          );
          // Same text, different Post: must remain a separate group.
          await receipt(
            id: 'other-share',
            beacon: _other,
            actor: _bob,
            name: 'Bob',
          );
          final email = await deliver(locale);
          final section = sectionsOf(email.html).values.single;
          expect(
            '/post/view/$_shared'.allMatches(section),
            hasLength(1),
            reason: 'One group per Post, even with two senders',
          );
          expect('/post/view/$_other'.allMatches(section), hasLength(1));
          for (final part in [section, email.text]) {
            expect(
              part,
              contains('${shared(locale, 'Alice')}: Read this before Saturday'),
            );
            expect(
              part,
              contains('${shared(locale, 'Bob')}: This made me think of you'),
            );
            expect(part, isNot(contains('Alice: This made me think of you')));
            expect(part, isNot(contains('Bob: Read this before Saturday')));
          }
          expect(
            RegExp('/post/view/$_shared\\?').allMatches(email.text),
            hasLength(1),
          );
          final marked = await session.writer.execute(
            'SELECT count(*) FROM public.notification_outbox WHERE emailed_at IS NOT NULL',
          );
          expect(
            marked.single.single,
            3,
            reason: 'All merged receipts are consumed',
          );
          final second = _DeliveredDigest();
          final env = Env(
            environment: Environment.test,
            publicOrigin: 'https://tentura.example',
            unsubscribeSigningSecret: 'digest-test-secret',
            printEnv: false,
          );
          await EmailDigestCase(
            NotificationPreferenceRepository(database),
            NotificationOutboxRepository(database),
            _Contacts(),
            second,
            EmailLinkBuilder(env),
            env,
            Logger('post-digest-test'),
            identity: NotificationIdentityRepository(database),
          ).runDue(
            now: DateTime.now().toUtc().copyWith(hour: env.emailDigestHour),
          );
          expect(second.messages, isEmpty);
        },
      );

      for (final (kind, en, ru) in [
        (
          'newRelay',
          'Alice shared a post with you: A personal note',
          'Alice делится с вами постом: A personal note',
        ),
        (
          'postFirstResponse',
          'Alice replied to your post',
          'Alice отвечает на ваш пост',
        ),
        (
          'postExpiringSoon',
          'Expires soon. Turn it into a request to keep it going',
          'Скоро исчезнет. Оформите запрос, чтобы продолжить',
        ),
      ]) {
        test(
          '$locale $kind is a line under the Post label with an absolute deep link',
          () async {
            final beacon = kind == 'newRelay' ? _shared : _own;
            await receipt(
              id: 'content',
              beacon: beacon,
              kind: kind,
              note: kind == 'newRelay' ? 'A personal note' : '',
            );
            final email = await deliver(locale);
            final line = locale == 'ru' ? ru : en;
            expect(
              email.text,
              contains('${postLabel(locale, _postBody)}\n'),
            );
            expect(email.text, contains('- $line\n'));
            expect(email.html, contains('<li>$line</li>'));
            final href = RegExp(
              '<li><a href="([^"]+)"',
            ).firstMatch(email.html)!.group(1)!;
            final url = Uri.parse(href.replaceAll('&amp;', '&'));
            expect(url.scheme, 'https');
            expect(url.host, 'tentura.example');
            expect(url.fragment, contains('/post/view/$beacon'));
            expect(email.text, contains(url.toString()));
          },
        );
      }
    }
  });
}

class _Contacts implements VerifiedContactRepositoryPort {
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async =>
      'reader@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _DeliveredDigest implements EmailSenderPort {
  final messages = <RenderedEmail>[];
  String? recipient;
  String? locale;
  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    recipient = to;
    this.locale = locale;
    messages.add(
      const EmailTemplateRenderer().renderDigest(
        content: content,
        locale: locale,
      ),
    );
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
