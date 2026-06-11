import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

import 'file_sink_email_sender.dart';
import 'resend_email_sender.dart';

/// Dev/prod email delivery: Resend by default; the file debug sink when
/// `EMAIL_DEBUG_SINK_DIR` is set (local + automated e2e flows). The test
/// environment keeps `LoggingEmailSender` via its own annotation.
@module
abstract class EmailSenderModule {
  @Singleton(env: [Environment.dev, Environment.prod], order: 1)
  EmailSenderPort emailSender(Env env) => env.emailDebugSinkDir.isNotEmpty
      ? FileSinkEmailSender(env)
      : ResendEmailSender(env);
}
