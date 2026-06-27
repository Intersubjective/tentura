import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/service/email/email_sink_writer.dart';
import 'package:tentura_server/data/service/email/qa_capturing_email_sender.dart';
import 'package:tentura_server/domain/entity/account_deletion_request_email_payload.dart';
import 'package:tentura_server/domain/entity/email_notification_content.dart';
import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

void main() {
  late Directory captureDir;
  late _RecordingEmailSender inner;

  setUp(() {
    captureDir = Directory.systemTemp.createTempSync('qa-capturing-sender-');
    inner = _RecordingEmailSender();
  });

  tearDown(() {
    captureDir.deleteSync(recursive: true);
    final defaultCapture = Directory(Env.kDefaultQaCaptureDir);
    if (defaultCapture.existsSync()) {
      for (final entity in defaultCapture.listSync()) {
        if (entity is File && entity.path.contains('qa-capturing-sender')) {
          entity.deleteSync();
        }
      }
    }
  });

  Env qaEnv({String capturePath = ''}) => Env(
    environment: Environment.test,
    emailDebugSinkDir: capturePath,
    qaAuthEnabled: true,
    qaAuthToken: 'secret',
    qaEmailDomains: const ['test.tentura.local'],
  );

  test('captures QA-domain magic links without calling inner sender', () async {
    const email = 'agent@test.tentura.local';
    final env = qaEnv();
    final sender = QaCapturingEmailSender(env, inner);

    await sender.sendMagicLink(
      to: email,
      verifyUrl: 'https://dev.tentura.io/auth/email/verify?t=qa',
      inviterName: 'Tester',
    );

    expect(inner.magicLinkCalls, isEmpty);
    final fileName = EmailSinkWriter.sanitizeEmailForFileName(email);
    final file = File('${Env.kDefaultQaCaptureDir}/$fileName.json');
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
    expect(file.existsSync(), isTrue);
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(json['to'], email);
    expect(json['verifyUrl'], contains('t=qa'));
    expect(json['inviterName'], 'Tester');
  });

  test('delegates non-QA magic links to inner sender', () async {
    final sender = QaCapturingEmailSender(qaEnv(), inner);

    await sender.sendMagicLink(
      to: 'real@gmail.com',
      verifyUrl: 'https://dev.tentura.io/auth/email/verify?t=real',
    );

    expect(inner.magicLinkCalls, hasLength(1));
    expect(inner.magicLinkCalls.single.to, 'real@gmail.com');
  });

  test('delegates notification and digest emails to inner sender', () async {
    final sender = QaCapturingEmailSender(qaEnv(), inner);

    await sender.sendNotificationEmail(
      to: 'agent@test.tentura.local',
      locale: 'en',
      content: const EmailNotificationContent(
        item: EmailNotificationItem(
          title: 'Title',
          body: 'Body',
          url: 'https://example.test/beacon/1',
        ),
        unsubscribeUrl: 'https://example.test/unsub',
        managePrefsUrl: 'https://example.test/prefs',
      ),
    );
    await sender.sendDigestEmail(
      to: 'agent@test.tentura.local',
      locale: 'en',
      content: const EmailDigestContent(
        sections: [],
        unsubscribeUrl: 'https://example.test/unsub',
        managePrefsUrl: 'https://example.test/prefs',
      ),
    );

    expect(inner.notificationCalls, 1);
    expect(inner.digestCalls, 1);
  });
}

final class _RecordingEmailSender implements EmailSenderPort {
  final magicLinkCalls = <({String to, String verifyUrl, String? inviterName})>[];
  var notificationCalls = 0;
  var digestCalls = 0;

  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {
    magicLinkCalls.add((to: to, verifyUrl: verifyUrl, inviterName: inviterName));
  }

  @override
  Future<void> sendNotificationEmail({
    required String to,
    required String locale,
    required EmailNotificationContent content,
    String? listUnsubscribeUrl,
  }) async {
    notificationCalls++;
  }

  @override
  Future<void> sendDigestEmail({
    required String to,
    required String locale,
    required EmailDigestContent content,
    String? listUnsubscribeUrl,
  }) async {
    digestCalls++;
  }

  @override
  Future<void> sendAccountDeletionRequestAdminEmail({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) async {}

  @override
  Future<void> sendAccountDeletionRequestUserConfirmation({
    required String to,
    required AccountDeletionRequestEmailPayload payload,
  }) async {}
}
