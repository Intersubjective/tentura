import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/service/email/email_link_builder.dart';
import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';
import 'package:tentura_server/domain/port/verified_contact_repository_port.dart';
import 'package:tentura_server/domain/use_case/email_test_case.dart';
import 'package:tentura_server/domain/util/debug_send_rate_limiter.dart';
import 'package:tentura_server/env.dart';

void main() {
  late _CapturingEmail sender;
  late DebugSendRateLimiter limiter;
  late EmailTestCase case_;
  late Env env;

  setUp(() {
    sender = _CapturingEmail();
    limiter = DebugSendRateLimiter();
    env = Env(
      environment: Environment.test,
      resendApiKey: 'key',
      resendFromEmail: 'from@example.com',
    );
    case_ = EmailTestCase(
      _FakeContacts('user@example.com'),
      _FakePrefs(
        NotificationPreferencesEntity(accountId: 'U1', locale: 'en'),
      ),
      EmailLinkBuilder(env),
      sender,
      limiter,
      env: env,
      logger: Logger('test'),
    );
  });

  test('sendTestEmail returns no_email when missing contact', () async {
    final noEmailCase = EmailTestCase(
      _FakeContacts(null),
      _FakePrefs(
        NotificationPreferencesEntity(accountId: 'U1', locale: 'en'),
      ),
      EmailLinkBuilder(env),
      sender,
      DebugSendRateLimiter(),
      env: env,
      logger: Logger('test'),
    );

    final result = await noEmailCase.sendTestEmail(userId: 'U1');

    expect(result['ok'], isFalse);
    expect(result['reason'], 'no_email');
    expect(sender.sent, isEmpty);
  });

  test('sendTestEmail sends notification email', () async {
    final result = await case_.sendTestEmail(userId: 'U1');

    expect(result['ok'], isTrue);
    expect(sender.sent, hasLength(1));
    expect(sender.sent.single.to, 'user@example.com');
  });

  test('sendTestEmail returns send_failed on transport error', () async {
    sender.throwOnSend = true;

    final result = await case_.sendTestEmail(userId: 'U1');

    expect(result['ok'], isFalse);
    expect(result['reason'], 'send_failed');
  });

  test('sendTestEmail is rate limited', () async {
    await case_.sendTestEmail(userId: 'U1');
    final result = await case_.sendTestEmail(userId: 'U1');

    expect(result['ok'], isFalse);
    expect(result['reason'], 'rate_limited');
    expect(sender.sent, hasLength(1));
  });
}

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

class _FakeContacts implements VerifiedContactRepositoryPort {
  _FakeContacts(this._email);
  final String? _email;

  @override
  Future<String?> getPrimaryEmailForAccount(String accountId) async => _email;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _CapturingEmail implements EmailSenderPort {
  final sent = <({String to, EmailNotificationContent content})>[];
  bool throwOnSend = false;

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async {
    if (throwOnSend) {
      throw Exception('send failed');
    }
    sent.add((to: to, content: content));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
