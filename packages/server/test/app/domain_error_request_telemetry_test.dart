import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';
import 'package:tentura_server/app/sentry/sentry_event_scrub.dart';
import 'package:tentura_server/app/sentry/sentry_request_tracing.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/env.dart';

class _RecordingTransport implements Transport {
  final events = <SentryEvent>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    for (final item in envelope.items) {
      if (item.originalObject case final SentryEvent event) {
        if (event is! SentryTransaction) events.add(event);
      }
    }
    return envelope.header.eventId;
  }
}

void main() {
  test(
    'request tracing preserves domain failures and retry hints without reporting them while unexpected codes still report',
    () async {
      final transport = _RecordingTransport();
      await Sentry.init((options) {
        options
          ..dsn = 'https://public@example.invalid/1'
          ..transport = transport
          ..tracesSampleRate = 1
          ..beforeSend = scrubAndFilterSentryEvent;
      });
      addTearDown(Sentry.close);
      final middleware = sentryRequestTracing(
        env: Env(sentryDsn: 'https://public@example.invalid/1'),
      );

      Future<ExceptionBase> invoke(ExceptionBase error) async {
        final handler = middleware((request) async => throw error);
        Object? propagated;
        try {
          await handler(
            Request(
              'POST',
              Uri.parse('http://localhost/api/v2/session/access-token'),
            ),
          );
        } catch (caught) {
          propagated = caught;
        }
        expect(
          propagated,
          same(error),
          reason:
              'Telemetry must leave the original failure available to the response handler',
        );
        return propagated! as ExceptionBase;
      }

      const unexpected = UnspecifiedException(
        description: 'Unexpected storage failure',
      );
      await invoke(unexpected);
      expect(
        transport.events.where((e) => identical(e.throwable, unexpected)),
        hasLength(1),
      );

      final busy = ConstellationException(
        constellationCode: ConstellationExceptionCode.retryLater,
        retryAfter: const Duration(milliseconds: 2400),
      );
      expect(busy.toMap['extensions'], containsPair('retryAfterMs', 2400));
      final expected = <ExceptionBase>[
        HelpOfferCoordinationException(
          coordinationCode: HelpOfferCoordinationExceptionCode.beaconNotOpen,
        ),
        const UnauthorizedException(
          description: 'Room or item thread access required',
        ),
        const BeaconLobbyAccessException(),
        const BeaconCreateException(description: 'Plan text is required'),
        busy,
      ];
      final leaked = <String>[];
      for (final error in expected) {
        final propagated = await invoke(error);
        if (identical(error, busy)) {
          expect(
            propagated,
            isA<ConstellationException>().having(
              (e) => e.retryAfter?.inMilliseconds,
              'propagated backoff',
              2400,
            ),
          );
          expect(
            propagated.toMap['extensions'],
            allOf(
              containsPair('code', '1704'),
              containsPair('retryAfterMs', 2400),
            ),
            reason:
                'The response handler must still be able to serialize the Busy retry hint',
          );
        }
        if (transport.events.any((e) => identical(e.throwable, error))) {
          leaked.add('${error.code.codeNumber}: ${error.description}');
        }
      }
      expect(
        leaked,
        isEmpty,
        reason: 'Expected domain failures must not create Sentry issues',
      );
    },
  );
}
