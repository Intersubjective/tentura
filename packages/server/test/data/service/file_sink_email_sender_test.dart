import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:tentura_server/data/service/email/file_sink_email_sender.dart';
import 'package:tentura_server/env.dart';

void main() {
  late Directory tempDir;
  late Env env;
  late FileSinkEmailSender sender;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('email-sink-test');
    env = Env(environment: 'test', emailDebugSinkDir: tempDir.path);
    sender = FileSinkEmailSender(env);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('writes verify URL as JSON named by sanitized address', () async {
    await sender.sendMagicLink(
      to: 'ada+test@example.com',
      verifyUrl: 'https://dev.lvh.me:9443/auth/email/verify?t=tok1',
      inviterName: 'Bob',
    );

    final file = File('${tempDir.path}/ada_test_example.com.json');
    expect(file.existsSync(), isTrue);
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(json['to'], 'ada+test@example.com');
    expect(json['verifyUrl'], contains('t=tok1'));
    expect(json['inviterName'], 'Bob');
    expect(json['sentAt'], isNotEmpty);
  });

  test('overwrites with the latest link for the same address', () async {
    await sender.sendMagicLink(
      to: 'ada@example.com',
      verifyUrl: 'https://x/auth/email/verify?t=old',
    );
    await sender.sendMagicLink(
      to: 'ada@example.com',
      verifyUrl: 'https://x/auth/email/verify?t=new',
    );

    final file = File('${tempDir.path}/ada_example.com.json');
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(json['verifyUrl'], contains('t=new'));
  });

  test('creates the sink directory when missing', () async {
    final nested = Env(
      environment: 'test',
      emailDebugSinkDir: '${tempDir.path}/nested/deeper',
    );
    await FileSinkEmailSender(nested).sendMagicLink(
      to: 'a@b.co',
      verifyUrl: 'https://x/verify?t=tok',
    );
    expect(File('${tempDir.path}/nested/deeper/a_b.co.json').existsSync(),
        isTrue);
  });

  test('debug sink alone makes email auth configured', () {
    expect(env.isEmailAuthConfigured, isTrue);
    expect(
      Env(environment: 'test').isEmailAuthConfigured,
      isFalse,
    );
    expect(
      Env(
        environment: 'test',
        resendApiKey: 're_x',
        resendFromEmail: 'auth@x.co',
      ).isEmailAuthConfigured,
      isTrue,
    );
  });

  test('sanitizeEmailForFileName strips path-hostile characters', () {
    expect(
      FileSinkEmailSender.sanitizeEmailForFileName('../../etc/passwd@x'),
      '.._.._etc_passwd_x',
    );
  });
}
