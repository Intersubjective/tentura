import 'dart:io';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' show ServerException;
import 'package:sentry/sentry.dart';
import 'package:shelf/shelf.dart' show HijackException;

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/request_context.dart';

/// Whether [error] is expected network churn that should not become a Sentry issue.
bool isBenignServerThrowable(Object? error) {
  if (error == null) {
    return false;
  }
  final disconnectReason = RequestContext.current?.clientDisconnectReason;
  if (disconnectReason != null &&
      (identical(error, disconnectReason) ||
          error is ServerException &&
              error.code == '57014' &&
              error.message == 'canceling statement due to user request')) {
    return true;
  }
  // Admission saturation is capacity backpressure on session routes too.
  if (error case ConstellationException(
    code: ConstellationExceptionCodes(
      exceptionCode: ConstellationExceptionCode.retryLater,
    ),
  )) {
    return true;
  }
  if (error is SocketException) {
    return true;
  }
  if (error is HttpException || error is TlsException) {
    return true;
  }
  if (error is HijackException) {
    return true;
  }
  final message = error.toString().toLowerCase();
  if (message.contains('socketexception') ||
      message.contains('connection reset') ||
      message.contains('broken pipe') ||
      message.contains('connection closed') ||
      message.contains('websocket') && message.contains('closed')) {
    return true;
  }
  return false;
}

bool isBenignSentryLogRecord(LogRecord record) {
  if (isBenignServerThrowable(record.error)) {
    return true;
  }
  final message = record.message.toLowerCase();
  if (message.contains('socketexception') ||
      message.contains('connection reset') ||
      message.contains('broken pipe')) {
    return true;
  }
  return false;
}

bool isBenignSentryEvent(SentryEvent event, Hint hint) {
  final synthetic = hint.get(TypeCheckHint.syntheticException);
  if (isBenignServerThrowable(synthetic)) {
    return true;
  }

  final exceptions = event.exceptions;
  if (exceptions == null) {
    return false;
  }

  for (final ex in exceptions) {
    final type = ex.type ?? '';
    if (type.contains('SocketException') ||
        type.contains('HttpException') ||
        type.contains('TlsException') ||
        type.contains('HijackException')) {
      return true;
    }
    final value = ex.value ?? '';
    if (value.toLowerCase().contains('socketexception') ||
        value.toLowerCase().contains('connection reset') ||
        value.toLowerCase().contains('broken pipe')) {
      return true;
    }
  }
  return false;
}
