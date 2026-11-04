@Tags(['pg'])
library;

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

/// Exercise persisted locale and receipts through the real repositories and
/// digest use case; only contact lookup and email transport are substituted.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_DIGEST_LOCALE_TEST_DB',
    defaultNamePrefix: 'tentura_test_digest_locale',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late TenturaDb database;
  late NotificationPreferenceRepository preferences;
  late NotificationOutboxRepository outbox;

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    database = openDisposablePgDatabase(target);
    preferences = NotificationPreferenceRepository(database);
    outbox = NotificationOutboxRepository(database);
    await session.writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Udigestru', 'Reader', 'digest-locale-reader-key')
''');
    await session.writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES ('Bdigestlocale', 'Udigestru', 'Request', 'Description', 0)
''');
  });
  tearDownAll(() async {
    await tearDownDisposablePgWriter(session: session, drift: database);
  });

  test(
    'persisted recipient locale selects the delivered digest fixed copy',
    () async {
      for (final locale in ['en', 'ru']) {
        await session.writer.execute('DELETE FROM public.notification_outbox');
        // Seed independently of the repository under test, and verify the
        // stored value through the writer connection before delivery reads it.
        await session.writer.execute(
          Sql.named('''
INSERT INTO public.notification_preference (
  account_id, locale, email_categories, email_digest
) VALUES (
  'Udigestru', @locale, ARRAY['asksOfMe', 'connections', 'coordination'], 'daily'
)
ON CONFLICT (account_id) DO UPDATE SET locale = EXCLUDED.locale
'''),
          parameters: {'locale': locale},
        );
        final stored = await session.writer.execute(
          "SELECT locale FROM public.notification_preference WHERE account_id = 'Udigestru'",
        );
        expect(stored.single.single, locale);
        expect((await preferences.getForAccount('Udigestru')).locale, locale);
        // Stored receipts have the producer's fixed English copy. The digest
        // must apply the reader's current preference at send time.
        for (final (category, kind, title, body) in const [
          (
            'asksOfMe',
            'needsMe',
            'Asked of you',
            'Action needed in the request discussion',
          ),
          (
            'coordination',
            'coordinationChanged',
            'Plan updated',
            'Coordination changed',
          ),
        ]) {
          await session.writer.execute(
            Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, source_event_key, destination_kind, presentation_key, access_policy,
  beacon_id, target_entity_id
) VALUES (
  gen_random_uuid()::text, 'Udigestru', @category, @kind, 'high',
  @title, @body, '/#/',
  @kind, @kind, 'beacon', @kind, 'beacon_content', 'Bdigestlocale', 'Bdigestlocale'
)
'''),
            parameters: {
              'category': category,
              'kind': kind,
              'title': title,
              'body': body,
            },
          );
        }
        final sender = _RenderedDigestSender();
        final env = target.databaseEnv;
        await EmailDigestCase(
          preferences,
          outbox,
          _Contacts(),
          sender,
          EmailLinkBuilder(env),
          env,
          Logger('digest-locale-test'),
          FakeBeaconAccessGuard(),
        ).runDue(now: DateTime.utc(2026, 11, 3, env.emailDigestHour));

        expect(sender.messages, hasLength(1));
        final delivered = sender.messages.single;
        expect(delivered.to, 'reader@example.com');
        expect(delivered.locale, locale);
        expect(
          delivered.rendered.subject,
          locale == 'ru' ? 'Сводка Tentura' : 'Your Tentura summary',
        );
        final manage = locale == 'ru'
            ? 'Настройки уведомлений'
            : 'Manage notifications';
        final unsubscribe = locale == 'ru' ? 'Отписаться' : 'Unsubscribe';
        final links = EmailLinkBuilder(env);
        final unsubscribeUrl = links.unsubscribeUrl(
          accountId: 'Udigestru',
          scope: 'all',
        );
        expect(
          delivered.rendered.html,
          contains('<a href="${links.manageUrl()}">$manage</a>'),
        );
        expect(
          delivered.rendered.html,
          contains('<a href="$unsubscribeUrl">$unsubscribe</a>'),
        );
        expect(
          delivered.rendered.text,
          contains('$manage: ${links.manageUrl()}'),
        );
        expect(
          delivered.rendered.text,
          contains('$unsubscribe: $unsubscribeUrl'),
        );
        expect(
          RegExp('<h3>(.*?)</h3>')
              .allMatches(delivered.rendered.html)
              .map((match) => match.group(1))
              .toList(),
          locale == 'ru'
              ? ['Ждёт вашего ответа', 'Изменилось, пока вас не было']
              : ['Waiting on you', 'Moved while you were away'],
        );
        for (final part in [delivered.rendered.html, delivered.rendered.text]) {
          if (locale == 'en') {
            expect(
              part,
              contains(
                "Here's what's waiting on you and what moved while you were away.",
              ),
            );
            expect(part, contains('Manage notifications'));
            expect(part, contains('Unsubscribe'));
            expect(part, contains('Waiting on you'));
            expect(part, contains('Moved while you were away'));
            expect(part, contains('Asked of you'));
            expect(part, contains('Plan updated'));
            expect(part, contains('Action needed in the request discussion'));
            expect(part, contains('Coordination changed'));
          } else {
            expect(
              part,
              contains('Вот что ждёт вас и что изменилось, пока вас не было.'),
            );
            expect(part, contains('Настройки уведомлений'));
            expect(part, contains('Отписаться'));
            expect(part, contains('Ждёт вашего ответа'));
            expect(part, contains('Изменилось, пока вас не было'));
            expect(part, isNot(contains('Waiting on you')));
            expect(part, isNot(contains('Moved while you were away')));
            expect(part, contains('Вас просят'));
            expect(part, contains('План обновлён'));
            expect(part, contains('В обсуждении запроса нужен ваш ответ'));
            expect(part, contains('Договорённости изменились'));
          }
        }
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
