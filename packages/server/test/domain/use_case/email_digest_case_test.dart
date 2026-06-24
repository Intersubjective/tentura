import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/service/email/email_link_builder.dart';
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
  ) async =>
      _pending;
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
  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
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
  ) =>
      NotificationOutboxItemEntity(
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
  }) =>
      NotificationPreferencesEntity(
        accountId: 'u1',
        emailCategories: email,
        emailDigest: cadence,
      );

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
    );

    await case_.runDue(now: dueNow);
    expect(sender.lastDigest!.totalItems, 1);
    expect(outbox.markedEmailed, ['a']);
  });
}
