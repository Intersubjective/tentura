import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

import 'file_sink_email_sender.dart';
import 'qa_capturing_email_sender.dart';
import 'resend_email_sender.dart';

/// Dev/prod email delivery: Resend by default; the file debug sink when
/// `EMAIL_DEBUG_SINK_DIR` is set (local + automated e2e flows); QA capture
/// decorator when `QA_AUTH_ENABLED` (remote dev agents). The test environment
/// keeps `LoggingEmailSender` via its own annotation.
@module
abstract class EmailSenderModule {
  @Singleton(env: [Environment.dev, Environment.prod], order: 1)
  EmailSenderPort emailSender(Env env) {
    if (env.emailDebugSinkDir.isNotEmpty) {
      return FileSinkEmailSender(env);
    }
    if (env.isQaAuthEnabled) {
      return QaCapturingEmailSender(env, ResendEmailSender(env));
    }
    return ResendEmailSender(env);
  }
}
