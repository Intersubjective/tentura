import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/service/email/test_domain_suppressing_email_sender.dart';
import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

void main() {
  Env env({bool? suppress}) => Env(
    environment: Environment.test,
    qaEmailDomains: const ['test.tentura.local', 'qa.tentura.local'],
    suppressTestDomainEmails: suppress,
  );

  test('EMAIL_SUPPRESS_TEST_DOMAINS is off by default', () {
    expect(env().suppressTestDomainEmails, isFalse);
  });

  group('Env.isTestClassEmail', () {
    final e = env();

    for (final email in [
      'agent@test.tentura.local',
      'Agent@TEST.tentura.local',
      'a@sub.test.tentura.local',
      'a@qa.tentura.local',
      'a@example.test',
      'a@foo.example',
      'a@foo.invalid',
      'a@localhost',
      'a@box.local',
      'a@example.com',
      'a@mail.example.org',
      'a@example.net',
    ]) {
      test('$email is test-class', () {
        expect(e.isTestClassEmail(email), isTrue);
      });
    }

    for (final email in [
      'real@gmail.com',
      'a@tentura.io',
      'a@notexample.com',
      'a@example.company',
      'a@testing.com',
      'no-at-sign',
      'a@',
    ]) {
      test('$email is not test-class', () {
        expect(e.isTestClassEmail(email), isFalse);
      });
    }
  });

  group('TestDomainSuppressingEmailSender', () {
    late _RecordingEmailSender inner;
    late TestDomainSuppressingEmailSender sender;

    setUp(() {
      inner = _RecordingEmailSender();
      sender = TestDomainSuppressingEmailSender(env(suppress: true), inner);
    });

    Future<void> sendAll(String to) async {
      await sender.sendMagicLink(to: to, verifyUrl: 'https://x/verify?t=1');
      await sender.sendNotificationEmail(
        to: to,
        locale: 'en',
        content: const EmailNotificationContent(
          item: EmailNotificationItem(
            title: 'Title',
            body: 'Body',
            url: 'https://tentura.io/beacon/1',
          ),
          unsubscribeUrl: 'https://tentura.io/unsub',
          managePrefsUrl: 'https://tentura.io/prefs',
        ),
      );
      await sender.sendDigestEmail(
        to: to,
        locale: 'en',
        content: const EmailDigestContent(
          sections: [],
          unsubscribeUrl: 'https://tentura.io/unsub',
          managePrefsUrl: 'https://tentura.io/prefs',
        ),
      );
      await sender.sendAccountDeletionRequestUserConfirmation(
        to: to,
        payload: _payload,
      );
      await sender.sendAccountDeletionRequestAdminEmail(
        to: to,
        payload: _payload,
      );
    }

    test('sends nothing to a test-class address', () async {
      await sendAll('agent@test.tentura.local');
      await sendAll('someone@example.com');

      expect(inner.recipients, isEmpty);
    });

    test('delivers every kind of email to a real address', () async {
      await sendAll('real@gmail.com');

      expect(inner.recipients, List.filled(5, 'real@gmail.com'));
    });
  });
}

final _payload = AccountDeletionRequestEmailPayload(
  complaintId: 'C1',
  userId: 'U1',
  contactEmail: 'agent@test.tentura.local',
  details: '',
  requestedAt: DateTime.utc(2026, 11),
);

final class _RecordingEmailSender implements EmailSenderPort {
  final recipients = <String>[];

  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async => recipients.add(to);

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async => recipients.add(to);

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async => recipients.add(to);

  @override
  Future<void> sendAccountDeletionRequestAdminEmail({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) async => recipients.add(to);

  @override
  Future<void> sendAccountDeletionRequestUserConfirmation({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) async => recipients.add(to);
}
