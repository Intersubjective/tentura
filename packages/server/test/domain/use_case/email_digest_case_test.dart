import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/data/service/email/templates/email_template_renderer.dart';
import 'package:tentura_server/domain/entity/digest_cadence.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/email_digest_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/fake_beacon_access_guard.dart';

class _FakePrefs implements NotificationPreferenceRepositoryPort {
  _FakePrefs(this._prefs);
  final NotificationPreferencesEntity _prefs;
  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async =>
      _prefs;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeOutbox implements NotificationOutboxRepositoryPort {
  _FakeOutbox(this._pending);
  final List<NotificationOutboxItemEntity> _pending;
  List<String>? markedEmailed;

  @override
  Future<List<String>> accountsWithPendingEmail() async => ['u1'];
  @override
  Future<DateTime?> lastEmailedAt(String accountId) async => null;
  @override
  Future<List<NotificationOutboxItemEntity>> pendingForAccount(
    String accountId,
  ) async => _pending;
  @override
  Future<int> markEmailed(List<String> ids) async {
    markedEmailed = ids;
    return ids.length;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _FakeContacts implements VerifiedContactRepositoryPort {
  _FakeContacts(this._email);
  final String? _email;
  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async => _email;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _CapturingEmail implements EmailSenderPort {
  EmailDigestContent? lastDigest;
  String? lastTo;
  String? lastLocale;
  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    lastLocale = locale;
    lastTo = to;
    lastDigest = content;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

void main() {
  final env = Env(
    environment: Environment.test,
    publicOrigin: 'https://t.example',
    unsubscribeSigningSecret: 'secret',
  );
  final links = EmailLinkBuilder(env);

  // Default EMAIL_DIGEST_HOUR is 8; tz offset 0 → pick 08:30 UTC as "due".
  final dueNow = DateTime.utc(2026, 6, 24, 8, 30);

  NotificationOutboxItemEntity item(
    String id,
    NotificationCategory category,
  ) => NotificationOutboxItemEntity(
    id: id,
    accountId: 'u1',
    category: category,
    kind: NotificationKind.needsMe,
    priority: NotificationPriority.high,
    title: 'T-$id',
    body: 'B-$id',
    actionUrl: '/#/x',
    createdAt: dueNow,
    collapsedCount: 1,
  );

  NotificationPreferencesEntity prefs({
    DigestCadence cadence = DigestCadence.daily,
    Set<NotificationCategory> email = const {
      NotificationCategory.asksOfMe,
      NotificationCategory.coordination,
    },
  }) => NotificationPreferencesEntity(
    accountId: 'u1',
    emailCategories: email,
    emailDigest: cadence,
  );

  group('digest follows the recipient language', () {
    Future<RenderedEmail> render(String locale) async {
      final sender = _CapturingEmail();
      final outbox = _FakeOutbox([
        item('ask', NotificationCategory.asksOfMe).copyWith(
          title: 'Asked of you',
          body: 'Action needed in the request discussion',
        ),
        item('plan', NotificationCategory.coordination).copyWith(
          kind: NotificationKind.coordinationChanged,
          title: 'Plan updated',
          body: 'Coordination changed',
        ),
      ]);
      await EmailDigestCase(
        _FakePrefs(prefs().copyWith(locale: locale)),
        outbox,
        _FakeContacts('u1@example.com'),
        sender,
        links,
        env,
        Logger('test'),
        FakeBeaconAccessGuard(),
      ).runDue(now: dueNow);
      expect(sender.lastLocale, locale);
      expect(sender.lastDigest?.totalItems, 2);
      return const EmailTemplateRenderer().renderDigest(
        content: sender.lastDigest!,
        locale: sender.lastLocale!,
      );
    }

    test(
      'both section headings use the recipient language in HTML and text',
      () async {
        for (final locale in ['en', 'ru']) {
          final email = await render(locale);
          expect(
            email.subject,
            locale == 'ru' ? 'Сводка Tentura' : 'Your Tentura summary',
          );
          final intro = locale == 'ru'
              ? 'Вот что ждёт вас и что изменилось, пока вас не было.'
              : "Here's what's waiting on you and what moved while you were away.";
          final manage = locale == 'ru'
              ? 'Настройки уведомлений'
              : 'Manage notifications';
          final unsubscribe = locale == 'ru' ? 'Отписаться' : 'Unsubscribe';
          final unsubscribeUrl = links.unsubscribeUrl(
            accountId: 'u1',
            scope: 'all',
          );
          expect(
            email.html,
            contains('<a href="${links.manageUrl()}">$manage</a>'),
          );
          expect(
            email.html,
            contains('<a href="$unsubscribeUrl">$unsubscribe</a>'),
          );
          expect(email.text, contains('$manage: ${links.manageUrl()}'));
          expect(email.text, contains('$unsubscribe: $unsubscribeUrl'));
          final headings = locale == 'ru'
              ? ['Ждёт вашего ответа', 'Изменилось, пока вас не было']
              : ['Waiting on you', 'Moved while you were away'];
          for (final part in [email.html, email.text]) {
            expect(part, contains(intro));
            for (final heading in headings) {
              expect(part, contains(heading));
            }
          }
          expect(
            RegExp(
              '<h3>(.*?)</h3>',
            ).allMatches(email.html).map((match) => match.group(1)).toList(),
            headings,
          );
        }
      },
    );

    test('fixed item titles and bodies use the recipient language', () async {
      for (final locale in ['en', 'ru']) {
        final email = await render(locale);
        for (final part in [email.html, email.text]) {
          for (final copy
              in locale == 'ru'
                  ? [
                      'Вас просят',
                      'В обсуждении запроса нужен ваш ответ',
                      'План обновлён',
                      'Договорённости изменились',
                    ]
                  : [
                      'Asked of you',
                      'Action needed in the request discussion',
                      'Plan updated',
                      'Coordination changed',
                    ]) {
            expect(part, contains(copy), reason: 'recipient locale: $locale');
          }
          expect(part, contains('https://t.example/'));
        }
      }
    });
  });

  test('sends digest with eligible items and marks them emailed', () async {
    final sender = _CapturingEmail();
    final outbox = _FakeOutbox([
      item('a', NotificationCategory.asksOfMe),
      item('c', NotificationCategory.coordination),
    ]);
    final case_ = EmailDigestCase(
      _FakePrefs(prefs()),
      outbox,
      _FakeContacts('u1@example.com'),
      sender,
      links,
      env,
      Logger('test'),
      FakeBeaconAccessGuard(),
    );

    await case_.runDue(now: dueNow);

    expect(sender.lastTo, 'u1@example.com');
    expect(sender.lastDigest!.totalItems, 2);
    // "Waiting on you" + "Moved while you were away".
    expect(sender.lastDigest!.sections.length, 2);
    expect(outbox.markedEmailed, containsAll(['a', 'c']));
  });

  test('digest off → no send', () async {
    final sender = _CapturingEmail();
    final outbox = _FakeOutbox([item('a', NotificationCategory.asksOfMe)]);
    final case_ = EmailDigestCase(
      _FakePrefs(prefs(cadence: DigestCadence.off)),
      outbox,
      _FakeContacts('u1@example.com'),
      sender,
      links,
      env,
      Logger('test'),
      FakeBeaconAccessGuard(),
    );

    await case_.runDue(now: dueNow);
    expect(sender.lastDigest, isNull);
    expect(outbox.markedEmailed, isNull);
  });

  test('not due hour → no send', () async {
    final sender = _CapturingEmail();
    final outbox = _FakeOutbox([item('a', NotificationCategory.asksOfMe)]);
    final case_ = EmailDigestCase(
      _FakePrefs(prefs()),
      outbox,
      _FakeContacts('u1@example.com'),
      sender,
      links,
      env,
      Logger('test'),
      FakeBeaconAccessGuard(),
    );

    // 14:30 UTC, tz 0 → local hour 14 != digest hour 8.
    await case_.runDue(now: DateTime.utc(2026, 6, 24, 14, 30));
    expect(sender.lastDigest, isNull);
  });

  test('only email-enabled categories are included', () async {
    final sender = _CapturingEmail();
    final outbox = _FakeOutbox([
      item('a', NotificationCategory.asksOfMe),
      item('c', NotificationCategory.coordination),
    ]);
    final case_ = EmailDigestCase(
      _FakePrefs(prefs(email: const {NotificationCategory.asksOfMe})),
      outbox,
      _FakeContacts('u1@example.com'),
      sender,
      links,
      env,
      Logger('test'),
      FakeBeaconAccessGuard(),
    );

    await case_.runDue(now: dueNow);
    expect(sender.lastDigest!.totalItems, 1);
    expect(outbox.markedEmailed, ['a']);
  });
}
