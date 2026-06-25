import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

/// Writes JSON email payloads to a directory for local dev and QA capture.
class EmailSinkWriter {
  EmailSinkWriter(this._dirPath, {required this.loggerName});

  final String _dirPath;
  final String loggerName;

  void write(String to, Map<String, dynamic> payload) {
    final dir = Directory(_dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/${sanitizeEmailForFileName(to)}.json')
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          ...payload,
          'sentAt': DateTime.timestamp().toIso8601String(),
        }),
      );
    Logger(loggerName).info(
      '${payload['kind']} for $to written to ${file.path}',
    );
  }

  /// `ada+test@example.com` → `ada_test_example.com` (path-safe, stable).
  static String sanitizeEmailForFileName(String email) =>
      email.replaceAll(RegExp(r'[^A-Za-z0-9.\-]'), '_');
}
