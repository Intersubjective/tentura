import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

import 'file_sink_email_sender.dart';
import 'qa_capturing_email_sender.dart';
import 'resend_email_sender.dart';
import 'test_domain_suppressing_email_sender.dart';

/// Dev/prod email delivery: Resend by default; the file debug sink when
/// `EMAIL_DEBUG_SINK_DIR` is set (local + automated e2e flows); test-class
/// addresses dropped before Resend when `EMAIL_SUPPRESS_TEST_DOMAINS`; QA
/// capture decorator outermost when `QA_AUTH_ENABLED` (remote dev agents), so
/// QA magic links are still captured. The test environment keeps
/// `LoggingEmailSender` via its own annotation.
@module
abstract class EmailSenderModule {
  @Singleton(env: [Environment.dev, Environment.prod], order: 1)
  EmailSenderPort emailSender(Env env) {
    if (env.emailDebugSinkDir.isNotEmpty) {
      return FileSinkEmailSender(env);
    }
    final delivery = env.suppressTestDomainEmails
        ? TestDomainSuppressingEmailSender(env, ResendEmailSender(env))
        : ResendEmailSender(env);
    if (env.isQaAuthEnabled) {
      return QaCapturingEmailSender(env, delivery);
    }
    return delivery;
  }
}
