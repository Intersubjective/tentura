import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/data/service/email_notification_service.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/env.dart';
import 'package:injectable/injectable.dart' show Environment;

class _FakePrefs implements NotificationPreferenceRepositoryPort {
  _FakePrefs(this._prefs);
  final NotificationPreferencesEntity _prefs;

  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async =>
      _prefs;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakePresence implements UserPresenceRepositoryPort {
  _FakePresence(this._presence);
  final UserPresenceEntity? _presence;

  @override
  Future<UserPresenceEntity?> get(String userId) async => _presence;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeContacts implements VerifiedContactRepositoryPort {
  _FakeContacts(this._email);
  final String? _email;

  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async => _email;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeOutbox implements NotificationOutboxRepositoryPort {
  _FakeOutbox({this.recentCount = 0});
  final int recentCount;
  final markedEmailed = <String>[];

  @override
  Future<int> countRecentEmailsByCategory({
    required String accountId,
    required NotificationCategory category,
    required Duration window,
  }) async =>
      recentCount;

  @override
  Future<int> markEmailedByDedupKey(String dedupKey) async {
    markedEmailed.add(dedupKey);
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _CapturingEmail implements EmailSenderPort {
  int notificationCount = 0;
  String? lastTo;

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async {
    notificationCount++;
    lastTo = to;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  final env = Env(
    environment: Environment.test,
    publicOrigin: 'https://t.example',
    unsubscribeSigningSecret: 'secret',
  );
  final links = EmailLinkBuilder(env);

  NotificationPreferencesEntity prefs({
    Set<NotificationCategory> email = const {NotificationCategory.asksOfMe},
  }) =>
      NotificationPreferencesEntity(accountId: 'u1', emailCategories: email);

  // A present, already-notified user (clearly-past timestamps → shouldNotify
  // false under the real wall clock).
  final presentUser = UserPresenceEntity(
    userId: 'u1',
    lastSeenAt: DateTime.utc(2020),
    lastNotifiedAt: DateTime.utc(2020, 1, 1, 0, 0, 1),
    offlineAfterDelay: const Duration(minutes: 5),
    status: UserPresenceStatus.online,
  );

  EmailNotificationService build({
    required NotificationPreferencesEntity p,
    required _CapturingEmail sender,
    required _FakeOutbox outbox,
    UserPresenceEntity? presence,
    String? email = 'u1@example.com',
  }) =>
      EmailNotificationService(
        _FakePrefs(p),
        _FakePresence(presence),
        sender,
        _FakeContacts(email),
        outbox,
        links,
        env,
        Logger('test'),
      );

  Future<void> consider(
    EmailNotificationService service, {
    NotificationKind kind = NotificationKind.needsMe,
    bool pushDelivered = false,
  }) =>
      service.considerImmediate(
        recipientUserId: 'u1',
        kind: kind,
        beaconId: 'b1',
        dedupKey: 'u1|asksOfMe|b1|',
        title: 'Asked of you',
        body: 'Please respond',
        actionUrl: '/#/beacon/view?id=b1&dest=room',
        pushDelivered: pushDelivered,
      );

  test('sends + marks emailed for absent asksOfMe recipient', () async {
    final sender = _CapturingEmail();
    final outbox = _FakeOutbox();
    await consider(build(p: prefs(), sender: sender, outbox: outbox));
    expect(sender.notificationCount, 1);
    expect(sender.lastTo, 'u1@example.com');
    expect(outbox.markedEmailed, ['u1|asksOfMe|b1|']);
  });

  test('no email for non-asksOfMe kind', () async {
    final sender = _CapturingEmail();
    await consider(
      build(p: prefs(), sender: sender, outbox: _FakeOutbox()),
      kind: NotificationKind.coordinationChanged,
    );
    expect(sender.notificationCount, 0);
  });

  test('no email when category email-disabled', () async {
    final sender = _CapturingEmail();
    await consider(build(p: prefs(email: {}), sender: sender, outbox: _FakeOutbox()));
    expect(sender.notificationCount, 0);
  });

  test('no email when no verified email exists', () async {
    final sender = _CapturingEmail();
    await consider(
      build(p: prefs(), email: null, sender: sender, outbox: _FakeOutbox()),
    );
    expect(sender.notificationCount, 0);
  });

  test('cooldown suppresses a second immediate email', () async {
    final sender = _CapturingEmail();
    await consider(
      build(p: prefs(), sender: sender, outbox: _FakeOutbox(recentCount: 1)),
    );
    expect(sender.notificationCount, 0);
  });

  test('present user with delivered push gets no email', () async {
    final sender = _CapturingEmail();
    await consider(
      build(p: prefs(), presence: presentUser, sender: sender, outbox: _FakeOutbox()),
      pushDelivered: true,
    );
    expect(sender.notificationCount, 0);
  });
}
