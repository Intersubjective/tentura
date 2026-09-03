import 'dart:io';

import 'package:logging/logging.dart';
import 'package:sentry/sentry.dart';
import 'package:shelf/shelf.dart' show HijackException;
import 'package:test/test.dart';

import 'package:tentura_server/app/sentry/sentry_benign_filter.dart';

void main() {
  group('isBenignServerThrowable', () {
    test('SocketException is benign', () {
      expect(
        isBenignServerThrowable(const SocketException('connection reset')),
        isTrue,
      );
    });

    test('connection reset message is benign', () {
      expect(
        isBenignServerThrowable(Exception('Connection reset by peer')),
        isTrue,
      );
    });

    test('unexpected server fault is not benign', () {
      expect(
        isBenignServerThrowable(StateError('boom')),
        isFalse,
      );
    });

    test('HijackException is benign', () {
      expect(
        isBenignServerThrowable(const HijackException()),
        isTrue,
      );
    });
  });

  group('isBenignSentryEvent', () {
    test('HijackException event is benign', () {
      final event = SentryEvent(
        exceptions: [
          SentryException(type: 'HijackException', value: 'hijacked'),
        ],
      );
      expect(isBenignSentryEvent(event, Hint()), isTrue);
    });
  });

  group('isBenignSentryLogRecord', () {
    test('severe log with SocketException is skipped', () {
      final record = LogRecord(
        Level.SEVERE,
        'socket failure',
        'TestLogger',
        const SocketException('broken pipe'),
      );
      expect(isBenignSentryLogRecord(record), isTrue);
    });
  });
}
