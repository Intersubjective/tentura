import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'package:tentura_server/domain/port/email_sender_port.dart';
import 'package:tentura_server/env.dart';

/// Dev-only delivery sink (`EMAIL_DEBUG_SINK_DIR`): writes the magic link to
/// `<dir>/<sanitized-email>.json` (overwrite = latest link per address) so
/// local and automated flows can read it from disk instead of a mailbox.
/// Selected over [ResendEmailSender] in `EmailSenderModule`; never registered
/// when the env var is unset.
class FileSinkEmailSender implements EmailSenderPort {
  FileSinkEmailSender(this._env);

  final Env _env;

  @override
  Future<void> sendMagicLink({
    required String to,
    required String verifyUrl,
    String? inviterName,
  }) async {
    final dir = Directory(_env.emailDebugSinkDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/${sanitizeEmailForFileName(to)}.json');
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'to': to,
        'verifyUrl': verifyUrl,
        'inviterName': inviterName,
        'sentAt': DateTime.timestamp().toIso8601String(),
      }),
    );
    Logger('FileSinkEmailSender').info(
      'magic link for $to written to ${file.path}',
    );
  }

  /// `ada+test@example.com` → `ada_test_example.com` (path-safe, stable).
  static String sanitizeEmailForFileName(String email) =>
      email.replaceAll(RegExp(r'[^A-Za-z0-9.\-]'), '_');
}
