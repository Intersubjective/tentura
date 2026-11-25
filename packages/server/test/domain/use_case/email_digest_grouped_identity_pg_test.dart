@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:characters/characters.dart';
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
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';

const _reader = 'Udgreader';
const _anna = 'Udganna';
const _bob = 'Udgbob';
const _owner = 'Udgowner';
const _roof = 'Bdgroof';
const _post = 'Bdgpost';
const _postRoot = 'Mdgpostroot';
const _readerEmail = 'reader@example.com';

/// Event-time name snapshots, as producers store them in the payload.
const _names = {_anna: 'Anna', _bob: 'Bob'};

/// The digest's `now`: the recipient's digest hour (tz offset 0).
final _now = DateTime.utc(2026, 11, 20, 8);

/// The digest email as the recipient gets it: outbox rows persisted in
/// Postgres the way the producers write them (presentation key + facts), read
/// by the real outbox/preference repositories, access guard and identity
/// resolver, rendered by the real template renderer and written by the
/// file-sink sender (`EMAIL_DEBUG_SINK_DIR`). Only the contact lookup is fake.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DIGEST_GROUPED_TEST_DB',
    defaultNamePrefix: 'tentura_test_digest_grouped',
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

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    database = openDisposablePgDatabase(target);
  });

  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  setUp(() async {
    sinkDir = Directory.systemTemp.createTempSync('digest_grouped_sink_');
    env = Env(
      environment: Environment.test,
      publicOrigin: 'https://t.example',
      unsubscribeSigningSecret: 'digest-grouped-secret',
      emailDebugSinkDir: sinkDir.path,
      emailDigestHour: 8,
      printEnv: false,
    );
    await _resetFixture(writer);
  });

  tearDown(() {
    if (sinkDir.existsSync()) sinkDir.deleteSync(recursive: true);
  });

  Future<void> setPreferences({
    String locale = 'en',
    bool lockScreenSafe = false,
    int tzOffsetMinutes = 0,
  }) => writer.execute(
    Sql.named('''
INSERT INTO public.notification_preference (
  account_id, locale, tz_offset_minutes, lock_screen_safe, email_digest,
  email_categories
) VALUES (
  @a, @l, @tz, @s, 'daily',
  ARRAY['asksOfMe', 'unblocksMe', 'coordination', 'connections',
        'ambient', 'postsSharedWithMe']
)
ON CONFLICT (account_id) DO UPDATE SET locale = EXCLUDED.locale,
  lock_screen_safe = EXCLUDED.lock_screen_safe,
  tz_offset_minutes = EXCLUDED.tz_offset_minutes
'''),
    parameters: {
      'a': _reader,
      'l': locale,
      's': lockScreenSafe,
      'tz': tzOffsetMinutes,
    },
  );

  /// One outbox row as its producer persists it. Stored title/body are
  /// deliberately stale English: the digest must not show them.
  Future<String> receipt({
    required String id,
    required String presentationKey,
    required String category,
    required String kind,
    required DateTime at,
    String? beacon,
    String? actor,
    Map<String, Object?> facts = const {},
    String title = 'STORED-TITLE',
    String body = 'STORED-BODY',
    String accessPolicy = 'beacon_content',
  }) async {
    final eventType = presentationKey.replaceAllMapped(
      RegExp('_([a-z])'),
      (m) => m.group(1)!.toUpperCase(),
    );
    final entity = beacon ?? actor;
    final url = beacon != null
        ? '/#/beacon/view/$beacon'
        : '/#/profile/view/$actor';
    await writer.execute(
      Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, source_event_key, destination_kind, target_entity_id,
  presentation_key, presentation_payload, access_policy, beacon_id,
  actor_user_id, created_at
) VALUES (
  @id, @reader, @category, @kind, 'normal', @title, @body, @url,
  @id, @id, @destination, @entity,
  @key, @payload::jsonb, @policy, @beacon,
  @actor, @at
)
'''),
      parameters: {
        'id': id,
        'reader': _reader,
        'category': category,
        'kind': kind,
        'title': title,
        'body': body,
        'url': url,
        'destination': beacon != null ? 'beacon' : 'profile',
        'entity': entity,
        'key': presentationKey,
        'payload': jsonEncode({
          'eventType': eventType,
          'beaconId': ?beacon,
          'targetEntityId': ?entity,
          'actorUserId': ?actor,
          if (actor != null) 'actorName': _names[actor],
          ...facts,
        }),
        'policy': accessPolicy,
        'beacon': beacon,
        'actor': actor,
        'at': at,
      },
    );
    return id;
  }

  Future<String> offer({
    String id = 'offer',
    String beacon = _roof,
    String actor = _anna,
    String excerpt = 'I can bring a ladder',
    DateTime? at,
  }) => receipt(
    id: id,
    presentationKey: 'help_offer_submitted',
    category: 'asksOfMe',
    kind: 'commitmentEvent',
    beacon: beacon,
    actor: actor,
    at: at ?? DateTime.utc(2026, 11, 19, 12),
    title: 'Anna',
    body: 'Anna offered help',
    facts: {'excerpt': excerpt},
  );

  Future<String> stale({int quietDays = 20, DateTime? at}) => receipt(
    id: 'stale',
    presentationKey: 'request_stale',
    category: 'asksOfMe',
    kind: 'staleRemind',
    beacon: _roof,
    at: at ?? DateTime.utc(2026, 11, 19, 9),
    title: 'Your request has gone quiet',
    body: 'Close it, extend it or post an update.',
    facts: {'staleReason': 'quiet', 'quietDays': quietDays},
  );

  Future<String> deadlineChanged({String beacon = _roof}) => receipt(
    id: 'deadline-$beacon',
    presentationKey: 'deadline_changed',
    category: 'coordination',
    kind: 'deadlineChanged',
    beacon: beacon,
    actor: _anna,
    at: DateTime.utc(2026, 11, 19, 11),
    title: 'Deadline changed',
    body: 'Deadline changed from none to 2026-11-25T18:00:00.000Z',
    facts: {'newEndAt': '2026-11-25T18:00:00.000Z'},
  );

  Future<String> postShare({
    String beacon = _post,
    String actor = _anna,
    DateTime? at,
  }) => receipt(
    id: 'share-$beacon-$actor',
    presentationKey: 'relay_received',
    category: 'postsSharedWithMe',
    kind: 'newRelay',
    beacon: beacon,
    actor: actor,
    at: at ?? DateTime.utc(2026, 11, 19, 10),
    title: 'Anna',
    body: 'Anna shared a post with you',
    facts: {'excerpt': 'Join us', 'beaconKind': 'post'},
  );

  Future<String> connection({String actor = _anna}) => receipt(
    id: 'connection-$actor',
    presentationKey: 'mutual_connection_formed',
    category: 'connections',
    kind: 'inviteAccepted',
    actor: actor,
    at: DateTime.utc(2026, 11, 19, 8),
    accessPolicy: 'profile',
  );

  Future<String> expiringSoon({required DateTime expiresAt}) async {
    await writer.execute(
      Sql.named('UPDATE public.beacon SET expires_at = @e WHERE id = @i'),
      parameters: {'e': expiresAt, 'i': 'Bdgownpost'},
    );
    return receipt(
      id: 'expiring',
      presentationKey: 'post_expiring_soon',
      category: 'coordination',
      kind: 'postExpiringSoon',
      beacon: 'Bdgownpost',
      at: DateTime.utc(2026, 11, 19, 7),
      title: 'Your post is about to expire',
      body: 'Your post expires in under 3 hours',
      facts: {'expiresAt': expiresAt.toUtc().toIso8601String()},
    );
  }

  /// The one wiring seam for EmailDigestCase. Today's seven dependencies,
  /// plus the live identity resolver offered in the usual shapes: the named
  /// `identity` argument (as in BeaconNotificationService and
  /// EmailNotificationService) or a ninth positional argument. If neither
  /// shape fits, today's constructor is used, so every test still runs its
  /// behavioural assertions. A different shape needs only this seam changed.
  EmailDigestCase digestCase() {
    final today = <Object?>[
      NotificationPreferenceRepository(database),
      NotificationOutboxRepository(database),
      _Contacts(),
      FileSinkEmailSender(env),
      EmailLinkBuilder(env),
      env,
      Logger('digest-grouped-test'),
    ];
    final identity = NotificationIdentityRepository(database);
    for (final (positional, named) in [
      (today, {#identity: identity}),
      ([...today, identity], const <Symbol, Object?>{}),
    ]) {
      try {
        return Function.apply(EmailDigestCase.new, positional, named)
            as EmailDigestCase;
        // A shape that does not fit surfaces as NoSuchMethodError; try the
        // next one.
        // ignore: avoid_catching_errors
      } on NoSuchMethodError {
        continue;
      }
    }
    return Function.apply(EmailDigestCase.new, today) as EmailDigestCase;
  }

  /// Runs the digest at the recipient's digest hour and returns what the
  /// file sink captured for the recipient.
  Future<_Digest> deliver({DateTime? now}) async {
    await digestCase().runDue(now: now ?? _now);
    final file = File(
      '${sinkDir.path}/'
      '${FileSinkEmailSender.sanitizeEmailForFileName(_readerEmail)}.json',
    );
    expect(file.existsSync(), isTrue, reason: 'one digest was written');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(json['kind'], 'digest');
    return _Digest(
      subject: json['subject'] as String,
      text: json['text'] as String,
      html: json['html'] as String,
    );
  }

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

  Future<bool> canRead(String beacon) async {
    final rows = await writer.execute(
      Sql.named('SELECT public.beacon_can_read_content(@b, @u)'),
      parameters: {'b': beacon, 'u': _reader},
    );
    return rows.single.single! as bool;
  }

  Future<bool> canReadTombstone(String beacon) async {
    final rows = await writer.execute(
      Sql.named('SELECT public.beacon_can_read_tombstone(@b, @u)'),
      parameters: {'b': beacon, 'u': _reader},
    );
    return rows.single.single! as bool;
  }

  Future<List<String>> seedFixtureEvents() async => [
    await offer(),
    await deadlineChanged(),
    await stale(),
    await postShare(),
    await connection(),
  ];

  group('Deadline times in recipient digest copy', () {
    for (final (locale, dateOnly, timed) in const [
      (
        'en',
        'Anna moved the deadline to 29 Nov',
        'Anna moved the deadline to 21 Nov, 18:00',
      ),
      (
        'ru',
        'Anna: новый срок — 29 ноября',
        'Anna: новый срок — 21 ноября, 18:00',
      ),
    ]) {
      test(
        '$locale shows a date at midnight and keeps an evening time',
        () async {
          const offset = 180;
          await setPreferences(locale: locale, tzOffsetMinutes: offset);
          for (final (id, deadline, at) in [
            ('evening', '2026-11-21T15:00:00Z', DateTime.utc(2026, 11, 19, 10)),
            (
              'midnight',
              '2026-11-28T21:00:00Z',
              DateTime.utc(2026, 11, 19, 11),
            ),
          ]) {
            await receipt(
              id: id,
              presentationKey: 'deadline_changed',
              category: 'coordination',
              kind: 'deadlineChanged',
              beacon: _roof,
              actor: _anna,
              at: at,
              title: 'Deadline changed',
              body: 'Deadline changed from none to $deadline',
              facts: {'newEndAt': deadline},
            );
          }

          final digest = await deliver(
            now: _now.subtract(const Duration(minutes: offset)),
          );
          expect(digest.text, contains('- $timed\n'));
          expect(digest.html, contains('<li>$timed</li>'));
          expect(digest.text, contains('- $dateOnly\n'));
          expect(digest.html, contains('<li>$dateOnly</li>'));
          expect(digest.text, isNot(contains('00:00')));
          expect(digest.html, isNot(contains('00:00')));
        },
      );
    }
  });

  group('digest text matches the expected-text fixtures', () {
    for (final locale in ['en', 'ru']) {
      test('$locale subject and text part equal digest_$locale.txt and every '
          'sent row is marked emailed', () async {
        await setPreferences(locale: locale);
        final ids = await seedFixtureEvents();
        final digest = await deliver();
        for (final id in ids) {
          expect(await emailed(id), isTrue, reason: 'sent row $id is marked');
        }
        final unsubscribeUrl = EmailLinkBuilder(
          env,
        ).unsubscribeUrl(accountId: _reader, scope: 'all');
        final actual =
            'Subject: ${digest.subject}\n\n'
            '${digest.text.replaceAll(unsubscribeUrl, '{unsubscribeUrl}')}\n';
        final expected = File(
          'test/fixtures/email/digest_$locale.txt',
        ).readAsStringSync();
        expect(actual, expected);
      });
    }
  });

  group('digest heading of a Post without text or image', () {
    const emptyPost = 'Bdgemptypost';
    const alice = 'Udgalice';

    Future<void> seedEmptyPost() async {
      await writer.execute(
        Sql.named(
          'INSERT INTO public."user" (id, display_name, public_key) '
          "VALUES (@id, 'Alice', @key)",
        ),
        parameters: {'id': alice, 'key': 'key-$alice'},
      );
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon (id, user_id, title, description, '
          'status, kind, forward_policy, published_at, is_discoverable) '
          "VALUES (@id, @a, '', '', 0, 1, 1, now(), false)",
        ),
        parameters: {'id': emptyPost, 'a': alice},
      );
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, '
          "body) VALUES ('Mdgemptyroot', @b, @a, '')",
        ),
        parameters: {'b': emptyPost, 'a': alice},
      );
      await writer.execute(
        "UPDATE public.beacon SET post_root_message_id = 'Mdgemptyroot' "
        "WHERE id = '$emptyPost'",
      );
      await writer.execute(
        Sql.named(
          'INSERT INTO public.beacon_forward_edge '
          '(id, beacon_id, sender_id, recipient_id, note) '
          "VALUES ('Fdgempty', @b, @s, @r, '')",
        ),
        parameters: {'b': emptyPost, 's': _anna, 'r': _reader},
      );
    }

    for (final (locale, label) in [
      ('en', 'Post · Alice'),
      ('ru', 'Пост · Alice'),
    ]) {
      test('$locale: a shared Post is grouped under «$label»', () async {
        await setPreferences(locale: locale);
        await seedEmptyPost();
        await postShare(beacon: emptyPost);
        final digest = await deliver();
        expect(digest.html, contains('>$label</a>'));
      });

      test('$locale: a reply to a Post is grouped under «$label»', () async {
        await setPreferences(locale: locale);
        await seedEmptyPost();
        await receipt(
          id: 'reply-$emptyPost',
          presentationKey: 'post_first_response',
          category: 'ambient',
          kind: 'postFirstResponse',
          beacon: emptyPost,
          actor: _bob,
          at: DateTime.utc(2026, 11, 19, 10),
          facts: {'excerpt': 'Count me in', 'beaconKind': 'post'},
        );
        final digest = await deliver();
        expect(digest.html, contains('>$label</a>'));
      });
    }
  });

  group('digest groups events by Request or Post within a section', () {
    test('two events about one Request share one linked heading, newest '
        'first, and each non-empty section has one heading', () async {
      await setPreferences();
      await seedFixtureEvents();
      // A second share of the same Post: still one Post group in its section.
      await postShare(actor: _bob, at: DateTime.utc(2026, 11, 19, 9, 30));
      final digest = await deliver();

      expect(
        RegExp(
          '<h3>(.*?)</h3>',
        ).allMatches(digest.html).map((m) => m.group(1)).toList(),
        [
          'Posts shared with you',
          'Waiting on you',
          'Moved while you were away',
          'People',
        ],
      );
      final sections = digest.html.split('<h3>').skip(1).toList();
      final shared = sections.firstWhere((s) => s.startsWith('Posts shared'));
      const postLink =
          '<a href="https://t.example/#/post/view/$_post">Post: '
          'Walk in the park</a>';
      expect(postLink.allMatches(shared), hasLength(1));
      expect('/#/post/view/$_post'.allMatches(shared), hasLength(1));
      final annaShareAt = shared.indexOf('Anna shared a post with you');
      final bobShareAt = shared.indexOf('Bob shared a post with you');
      expect(annaShareAt, greaterThan(shared.indexOf(postLink)));
      expect(bobShareAt, greaterThan(annaShareAt), reason: 'newest first');
      final waiting = sections.firstWhere((s) => s.startsWith('Waiting'));
      const roofLink =
          '<a href="https://t.example/#/beacon/view/$_roof">Fix the roof</a>';
      expect(roofLink.allMatches(waiting), hasLength(1));
      final offerAt = waiting.indexOf(
        'Anna offered help: I can bring a ladder',
      );
      final staleAt = waiting.indexOf('No activity for 20 days');
      expect(offerAt, greaterThan(waiting.indexOf(roofLink)));
      expect(staleAt, greaterThan(offerAt), reason: 'newest event first');
      final moved = sections.firstWhere((s) => s.startsWith('Moved'));
      expect(roofLink.allMatches(moved), hasLength(1));
      expect(moved, contains('Anna moved the deadline to 25 Nov, 18:00'));
    });
  });

  group('bullet text is rendered from the event facts and live identity', () {
    test('a stale reminder stored in English reads in Russian for a Russian '
        'recipient', () async {
      await setPreferences(locale: 'ru');
      await stale(quietDays: 5);
      final digest = await deliver();
      for (final part in [digest.text, digest.html]) {
        expect(
          part,
          contains(
            '5 дней без движения. Закройте, продлите или напишите новости',
          ),
        );
        expect(part, isNot(contains('Your request has gone quiet')));
        expect(part, isNot(contains('STORED')));
      }
    });

    for (final (locale, sentence) in [
      ('en', 'Anna offered help: I can bring a ladder'),
      ('ru', 'Anna предлагает помощь: I can bring a ladder'),
    ]) {
      test('$locale help offer bullet names the person and quotes the '
          'offer', () async {
        await setPreferences(locale: locale);
        await offer();
        final digest = await deliver();
        expect(digest.text, contains('- $sentence'));
        expect(digest.html, contains(sentence));
      });
    }

    test('the bullet uses the name the person has now', () async {
      await setPreferences();
      await offer();
      await writer.execute(
        "UPDATE public.\"user\" SET display_name = 'Anna K' WHERE id = '$_anna'",
      );
      final digest = await deliver();
      expect(
        digest.text,
        contains('- Anna K offered help: I can bring a ladder'),
      );
      expect(digest.html, contains('Anna K offered help'));
    });

    for (final (locale, sentence) in [
      ('en', 'Someone offered help: I can bring a ladder'),
      ('ru', 'Кто-то предлагает помощь: I can bring a ladder'),
    ]) {
      test('$locale bullet says «${sentence.split(' ').first}» when the '
          'person has no display name', () async {
        await setPreferences(locale: locale);
        await offer();
        await writer.execute(
          "UPDATE public.\"user\" SET display_name = '' WHERE id = '$_anna'",
        );
        final digest = await deliver();
        expect(digest.text, contains('- $sentence'));
        expect(digest.html, contains(sentence));
      });
    }
  });

  group('rows the recipient cannot place under a readable Request', () {
    test('an unreadable Request is an ungrouped «headline — sentence» bullet '
        'and its title appears nowhere', () async {
      await setPreferences();
      expect(await canRead('Bdgsecret'), isFalse, reason: 'really unreadable');
      await offer(id: 'secret-offer', beacon: 'Bdgsecret');
      final digest = await deliver();
      expect(digest.text, contains('- Help offered — Anna offered help'));
      expect(digest.html, contains('Help offered — Anna offered help'));
      for (final part in [digest.subject, digest.text, digest.html]) {
        expect(part, isNot(contains('Secret plans')));
      }
      expect(digest.subject, 'Your Tentura summary');
    });

    for (final (locale, heading, bullet) in [
      ('en', 'People', 'New connection — You and Anna are now connected'),
      ('ru', 'Люди', 'Новая связь — Вы и Anna теперь на связи'),
    ]) {
      test('$locale entity-less connection rows go under «$heading»', () async {
        await setPreferences(locale: locale);
        await connection();
        final digest = await deliver();
        expect(digest.html, contains('<h3>$heading</h3>'));
        expect(digest.html, contains(bullet));
        expect(digest.text, contains('$heading\n- $bullet\n'));
      });
    }
  });

  group('digest subject names the top item', () {
    test('one readable group names it', () async {
      await setPreferences();
      await offer();
      expect((await deliver()).subject, 'Tentura: «Fix the roof»');
    });

    for (final (locale, subject) in [
      ('en', 'Tentura: «Fix the roof» and 2 more'),
      ('ru', 'Tentura: «Fix the roof» и ещё 2'),
    ]) {
      test('$locale three groups name the first group of the first non-empty '
          'section and count the rest', () async {
        await setPreferences(locale: locale);
        // «Fix the roof» is the only group in «Waiting on you»; the other two
        // Requests are groups in the later «Moved while you were away».
        await offer();
        await deadlineChanged(beacon: 'Bdgfence');
        await deadlineChanged(beacon: 'Bdggarden');
        expect((await deliver()).subject, subject);
      });
    }

    for (final (locale, subject) in [
      ('en', 'Your Tentura summary'),
      ('ru', 'Сводка Tentura'),
    ]) {
      test('$locale lock-screen-safe recipients get the generic subject even '
          'with readable groups', () async {
        await setPreferences(locale: locale, lockScreenSafe: true);
        await offer();
        final digest = await deliver();
        expect(digest.subject, subject);
        expect(digest.subject, isNot(contains('Fix the roof')));
      });
    }

    for (final (locale, subject, sentence) in [
      ('en', 'Your Tentura summary', 'You and Anna are now connected'),
      ('ru', 'Сводка Tentura', 'Вы и Anna теперь на связи'),
    ]) {
      test(
        '$locale only an entity-less row gives the generic subject',
        () async {
          await setPreferences(locale: locale);
          await connection();
          final digest = await deliver();
          expect(digest.subject, subject);
          expect(digest.html, contains(sentence));
        },
      );
    }

    for (final (locale, sentence) in [
      ('en', 'New connection — You and Someone are now connected'),
      ('ru', 'Новая связь — Вы и Кто-то теперь на связи'),
    ]) {
      test('$locale a connection with a person who has no display name says '
          '«${locale == 'en' ? 'Someone' : 'Кто-то'}»', () async {
        await setPreferences(locale: locale);
        await connection();
        await writer.execute(
          "UPDATE public.\"user\" SET display_name = '' WHERE id = '$_anna'",
        );
        final digest = await deliver();
        expect(digest.text, contains('- $sentence'));
        for (final part in [digest.subject, digest.text, digest.html]) {
          expect(part, isNot(contains('Anna')));
        }
      });
    }
  });

  group('deleted Requests and Posts', () {
    for (final (locale, label, bullet) in [
      ('ru', 'Удалённый запрос', 'Anna: новый срок — 25 ноября, 18:00'),
      ('en', 'Deleted request', 'Anna moved the deadline to 25 Nov, 18:00'),
    ]) {
      test(
        '$locale a readable tombstone groups the row under «$label»',
        () async {
          await setPreferences(locale: locale);
          expect(await canReadTombstone('Bdgshed'), isTrue);
          await deadlineChanged(beacon: 'Bdgshed');
          final digest = await deliver();
          expect(digest.text, contains('$label\n'));
          expect(digest.text, contains('- $bullet\n'));
          expect(digest.html, contains(label));
          for (final part in [digest.subject, digest.text, digest.html]) {
            expect(part, isNot(contains('Old shed')));
            expect(part, isNot(contains('Request no longer available')));
          }
        },
      );
    }

    for (final (locale, label) in [
      ('ru', 'Удалённый пост'),
      ('en', 'Deleted post'),
    ]) {
      test('$locale a deleted Post groups the row under «$label»', () async {
        await setPreferences(locale: locale);
        await postShare(beacon: 'Bdgdelpost');
        final digest = await deliver();
        expect(digest.text, contains('$label\n'));
        expect(digest.html, contains(label));
        for (final part in [digest.text, digest.html]) {
          expect(part, isNot(contains('Old photo walk')));
        }
      });
    }

    test('a deleted Request whose tombstone is unreadable is absent', () async {
      await setPreferences();
      expect(await canRead('Bdggone'), isFalse);
      expect(await canReadTombstone('Bdggone'), isFalse);
      await connection();
      await deadlineChanged(beacon: 'Bdggone');
      final digest = await deliver();
      for (final part in [digest.subject, digest.text, digest.html]) {
        expect(part, isNot(contains('Anna moved the deadline')));
        expect(part, isNot(contains('Deadline changed')));
        expect(part, isNot(contains('Gone garage')));
        expect(part, isNot(contains('Deleted request')));
      }
      expect(digest.text, contains('You and Anna are now connected'));
    });

    test('a deleted Post whose tombstone is unreadable is absent', () async {
      await setPreferences();
      expect(await canRead('Bdggonepost'), isFalse);
      expect(await canReadTombstone('Bdggonepost'), isFalse);
      await connection();
      await postShare(beacon: 'Bdggonepost');
      final digest = await deliver();
      for (final part in [digest.subject, digest.text, digest.html]) {
        expect(part, isNot(contains('Anna shared a post with you')));
        expect(part, isNot(contains('Post shared')));
        expect(part, isNot(contains('Posts shared with you')));
        expect(part, isNot(contains('Deleted post')));
        expect(part, isNot(contains('Lost lake trip')));
      }
      expect(digest.text, contains('You and Anna are now connected'));
    });
  });

  group('expiring Post warnings', () {
    test('a warning for a Post that already expired is absent and left '
        'unmarked', () async {
      await setPreferences();
      final sent = await connection();
      final expired = await expiringSoon(
        expiresAt: _now.subtract(const Duration(hours: 1)),
      );
      final digest = await deliver();
      for (final part in [digest.subject, digest.text, digest.html]) {
        expect(part, isNot(contains('Expiring soon')));
        expect(part, isNot(contains('Turn it into a request')));
        expect(part, isNot(contains('Expires in')));
        expect(part, isNot(contains('Your post expires soon')));
        expect(part, isNot(contains('Sunset by the river')));
      }
      expect(digest.text, contains('You and Anna are now connected'));
      expect(await emailed(sent), isTrue, reason: 'the sent row is marked');
      expect(await emailed(expired), isFalse, reason: 'dropped row unmarked');
    });

    test(
      'a Russian warning for an expired Post is absent and left unmarked',
      () async {
        await setPreferences(locale: 'ru');
        final sent = await connection();
        final expired = await expiringSoon(
          expiresAt: _now.subtract(const Duration(hours: 1)),
        );
        final digest = await deliver();
        for (final part in [digest.text, digest.html]) {
          expect(part, isNot(contains('Скоро истекают')));
          expect(part, isNot(contains('Оформите запрос')));
          expect(part, isNot(contains('Исчезнет через')));
          expect(part, isNot(contains('Ваш пост скоро исчезнет')));
          expect(part, isNot(contains('Sunset by the river')));
        }
        expect(digest.text, contains('Вы и Anna теперь на связи'));
        expect(await emailed(sent), isTrue, reason: 'the sent row is marked');
        expect(await emailed(expired), isFalse, reason: 'dropped row unmarked');
      },
    );

    for (final (locale, section, label, bullet) in [
      (
        'en',
        'Expiring soon',
        'Post: Sunset by the river',
        'Expires in 2 h. Turn it into a request to keep it going',
      ),
      (
        'ru',
        'Скоро истекают',
        'Пост: Sunset by the river',
        'Исчезнет через 2 ч. Оформите запрос, чтобы продолжить',
      ),
    ]) {
      test('$locale a Post with 2 hours left is warned about under its '
          'label', () async {
        await setPreferences(locale: locale);
        await expiringSoon(expiresAt: _now.add(const Duration(hours: 2)));
        final digest = await deliver();
        expect(
          digest.text,
          contains(
            '$section\n$label\n'
            '  https://t.example/#/post/view/Bdgownpost\n'
            '- $bullet\n',
          ),
        );
        expect(digest.html, contains('<h3>$section</h3>'));
        expect(digest.html, contains(bullet));
      });
    }
  });

  group('rows from a blocked person', () {
    for (final (direction, blocker, blocked) in [
      ('the recipient blocked the actor', _reader, _anna),
      ('the actor blocked the recipient', _anna, _reader),
    ]) {
      test('are dropped and left unmarked when $direction; the other rows '
          'are sent and marked', () async {
        await setPreferences();
        final dropped = await offer();
        final kept = await offer(
          id: 'bob-offer',
          beacon: 'Bdgfence',
          actor: _bob,
          excerpt: 'I have paint',
          at: DateTime.utc(2026, 11, 19, 11),
        );
        await writer.execute(
          Sql.named(
            'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
            'VALUES (@a, @b, @a)',
          ),
          parameters: {'a': blocker, 'b': blocked},
        );
        final digest = await deliver();
        for (final part in [digest.subject, digest.text, digest.html]) {
          expect(part, isNot(contains('Anna')));
          expect(part, isNot(contains('I can bring a ladder')));
        }
        expect(digest.text, contains('- Bob offered help: I have paint'));
        expect(await emailed(kept), isTrue);
        expect(await emailed(dropped), isFalse);
      });
    }
  });

  group('text safety', () {
    test('a Request title with markup is escaped in the HTML heading', () async {
      await setPreferences();
      await writer.execute(
        "UPDATE public.beacon SET title = 'Roof <b>&\" fix' WHERE id = '$_roof'",
      );
      await offer();
      final digest = await deliver();
      expect(
        digest.html,
        contains(
          '<a href="https://t.example/#/beacon/view/$_roof">Roof '
          '&lt;b&gt;&amp;&quot; fix</a>',
        ),
      );
      expect(digest.html, isNot(contains('<b>&"')));
      expect(digest.text, contains('Roof <b>&" fix\n'));
      expect(digest.subject, 'Tentura: «Roof <b>&" fix»');
    });

    test('a long Request title is shortened so the group heading stays '
        'within 80 graphemes', () async {
      await setPreferences();
      final longTitle =
          '${List.filled(12, 'Repair').join(' ')} the leaking roof above the '
          'old barn';
      expect(longTitle.characters.length, greaterThan(100));
      await writer.execute(
        Sql.named('UPDATE public.beacon SET title = @t WHERE id = @i'),
        parameters: {'t': longTitle, 'i': _roof},
      );
      await offer();
      final digest = await deliver();
      final headings = [
        for (final line in digest.text.split('\n'))
          if (line.startsWith('Repair Repair')) line,
      ];
      expect(headings, hasLength(1), reason: 'one group heading');
      final heading = headings.single;
      expect(heading.characters.length, lessThanOrEqualTo(80));
      expect(heading, endsWith('…'));
      expect(digest.text, isNot(contains(longTitle)));
    });

    test('a long excerpt is shortened first so the bullet line stays within '
        '160 graphemes', () async {
      await setPreferences();
      final longExcerpt = List.filled(60, 'ladder').join(' ');
      await offer(excerpt: longExcerpt);
      final digest = await deliver();
      final bullets = [
        for (final line in digest.text.split('\n'))
          if (line.startsWith('- Anna offered help: ')) line,
      ];
      expect(bullets, hasLength(1), reason: 'one bullet for the offer');
      final bullet = bullets.single;
      expect(bullet.characters.length, lessThanOrEqualTo(160));
      expect(bullet, endsWith('…'));
    });
  });
}

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE
  public.notification_outbox,
  public.notification_preference,
  public.user_block,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon_room_message,
  public.beacon,
  public."user"
CASCADE
''');
  for (final (id, name) in [
    (_reader, 'Reader'),
    (_anna, 'Anna'),
    (_bob, 'Bob'),
    (_owner, 'Owner'),
  ]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$name', 'key-$id')
''');
  }
  // Requests: the reader's own (readable), someone else's private one
  // (unreadable), a deleted one the reader took part in (tombstone readable)
  // and a deleted one the reader never saw (tombstone unreadable).
  for (final (id, author, title, status) in [
    (_roof, _reader, 'Fix the roof', 0),
    ('Bdgfence', _reader, 'Paint the fence', 0),
    ('Bdggarden', _reader, 'Water the garden', 0),
    ('Bdgsecret', _owner, 'Secret plans', 0),
    ('Bdgshed', _owner, 'Old shed', 0),
    ('Bdggone', _owner, 'Gone garage', 0),
  ]) {
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, published_at,
   is_discoverable)
VALUES (@id, @author, @title, '', @status, 0, now(), false)
'''),
      parameters: {
        'id': id,
        'author': author,
        'title': title,
        'status': status,
      },
    );
  }
  await writer.execute('''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pdgshed', 'Bdgshed', '$_reader', 0, 0, 3)
''');
  // Posts: shared with the reader, shared then deleted, and the reader's own.
  for (final (id, author, rootId, body) in [
    (_post, _owner, _postRoot, 'Walk in the park'),
    ('Bdgdelpost', _owner, 'Mdgdelpost', 'Old photo walk'),
    ('Bdgownpost', _reader, 'Mdgownpost', 'Sunset by the river'),
    ('Bdggonepost', _owner, 'Mdggonepost', 'Lost lake trip'),
  ]) {
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   published_at, is_discoverable)
VALUES ('$id', '$author', '', '', 0, 1, 1, now(), false)
''');
    await writer.execute(
      Sql.named('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES (@m, @b, @a, @body)
'''),
      parameters: {'m': rootId, 'b': id, 'a': author, 'body': body},
    );
    await writer.execute(
      "UPDATE public.beacon SET post_root_message_id = '$rootId' "
      "WHERE id = '$id'",
    );
  }
  for (final (id, post) in [('Fdgpost', _post), ('Fdgdelpost', 'Bdgdelpost')]) {
    await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id, note)
VALUES ('$id', '$post', '$_anna', '$_reader', 'Join us')
''');
  }
  await writer.execute(
    'UPDATE public.beacon SET status = 2 '
    "WHERE id IN ('Bdgshed', 'Bdggone', 'Bdgdelpost', 'Bdggonepost')",
  );
}

class _Digest {
  const _Digest({
    required this.subject,
    required this.text,
    required this.html,
  });

  final String subject;
  final String text;
  final String html;
}

final class _Contacts implements VerifiedContactRepositoryPort {
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async =>
      accountId == _reader ? _readerEmail : null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}
