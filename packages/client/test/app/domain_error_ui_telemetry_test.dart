import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:gql_exec/gql_exec.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/app/sentry/report_sentry_message.dart';
import 'package:tentura/app/sentry/report_user_facing_error.dart';
import 'package:tentura/app/sentry/sentry_init.dart';
import 'package:tentura/data/service/remote_api_client/auth_loss_classifier.dart';
import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/beacon_lobby/data/model/beacon_lobby_error_mapper.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_lobby/ui/bloc/beacon_lobby_cubit.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_chat.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_dispatcher.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../features/beacon_lobby/fake_lobby_port.dart';

// A wire denial crosses the production code mapper before reaching the real
// Questions cubit and view. The fake supplies only the remote response.
class _DeniedQuestionsPort extends FakeLobbyPort {
  _DeniedQuestionsPort(this.wire) : super(viewerId: 'Ustranger');

  final GraphQLError wire;
  Object? denial;

  @override
  Future<BeaconLobbyInfo> open(String beaconId) async {
    try {
      throwIfBeaconLobbyError(int.parse(wire.extensions!['code'].toString()));
    } catch (error) {
      denial = error;
      rethrow;
    }
    return super.open(beaconId);
  }
}

class _UnusedRouter extends Mock implements RootRouter {}

class _RecordingTransport implements Transport {
  final events = <SentryEvent>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    for (final item in envelope.items) {
      if (item.originalObject case final SentryEvent event) {
        events.add(event);
      }
    }
    return envelope.header.eventId;
  }
}

const _cases = [
  (
    code: '1500',
    message: 'beaconNotOpen',
    en: 'This request is in its final check or closed, so it no longer takes offers or changes.',
    ru: 'Запрос на подведении итогов или закрыт, поэтому больше не принимает предложения и изменения.',
  ),
  (
    code: '1102',
    message: 'Room or item thread access required',
    en: "You don't have access to this.",
    ru: 'У вас нет доступа к этому.',
  ),
  (
    code: '1347',
    message: 'Questions are for the people this request was sent to',
    en: 'Questions are for the people this request was sent to.',
    ru: 'Вопросы доступны тем, кому отправлен этот запрос.',
  ),
  (
    code: '1301',
    message: 'Plan text is required',
    en: 'Plan text is required',
    ru: 'Plan text is required',
  ),
  (
    code: '1704',
    message: 'Busy right now. Try again in a few seconds.',
    en: 'Busy right now. Try again in a few seconds.',
    ru: 'Сервер занят. Попробуйте ещё раз через несколько секунд.',
  ),
];

void main() {
  late _RecordingTransport transport;

  setUp(() async {
    transport = _RecordingTransport();
    final options = SentryFlutterOptions();
    configureSentryOptions(options);
    options
      ..dsn = 'https://public@example.invalid/1'
      ..transport = transport
      ..tracesSampleRate = 0
      ..enableLogs = false;
    // ignore: invalid_use_of_internal_member
    await Sentry.init((_) {}, options: options);
    GetIt.I
      ..registerSingleton<RootRouter>(_UnusedRouter())
      ..registerSingleton<Logger>(Logger.detached('domain-error-test'));
  });

  tearDown(() async {
    await Sentry.close();
    await GetIt.I.reset();
  });

  // These reporters are fire-and-forget. A delivered control event proves
  // the SDK is enabled and gives earlier reports time to reach the transport.
  Future<void> drain(String marker) async {
    reportUserFacingError(StateError(marker));
    for (var i = 0; i < 100; i++) {
      if (transport.events.any(
        (e) => e.throwable.toString().contains(marker),
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Unexpected control failure did not reach Sentry: $marker');
  }

  group('domain failures preserve translated UI without creating Sentry issues', () {
    for (final includeDiagnostics in [false, true]) {
      for (final locale in ['en', 'ru']) {
        testWidgets(
          '${includeDiagnostics ? 'GraphQL wrappers and timeout diagnostics' : 'Mapped GraphQL failures'} preserve translated UI in $locale',
          (tester) async {
            final leaked = <String>[];
            var sequence = 0;

            Future<List<SentryEvent>> show(
              Object error,
              String expected, {
              GraphQLError? wire,
              List<Object> diagnostics = const [],
              String? messageDiagnostic,
            }) async {
              final before = transport.events.length;
              final port = wire?.extensions?['code'] == '1347'
                  ? _DeniedQuestionsPort(wire!)
                  : null;
              final cubit = port == null
                  ? null
                  : BeaconLobbyCubit(
                      lobbyCaseFor(port, FakeRealtimeSyncPort()),
                      RecordingEffects(),
                      beaconId: 'B1',
                    );
              await tester.pumpWidget(
                MaterialApp(
                  key: ValueKey(sequence++),
                  theme: TenturaTheme.light(),
                  locale: Locale(locale),
                  localizationsDelegates: L10n.localizationsDelegates,
                  supportedLocales: L10n.supportedLocales,
                  home: Builder(
                    builder: (context) => Scaffold(
                      body: Column(
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              if (cubit != null) {
                                await cubit.load();
                                expect(port!.denial, isNotNull);
                                reportUserFacingError(port.denial!);
                                // The denial view owns Questions copy; an error
                                // reporter receiving the original wire failure must
                                // independently suppress its telemetry.
                                reportUserFacingError(error);
                              } else {
                                dispatchUiEffect(
                                  context,
                                  ShowError(error),
                                  localeName: locale,
                                );
                              }
                              for (final diagnostic in diagnostics) {
                                reportUserFacingError(diagnostic);
                              }
                              if (messageDiagnostic != null) {
                                reportSentryMessage(messageDiagnostic);
                              }
                            },
                            child: const Text('Show error'),
                          ),
                          if (cubit != null)
                            Expanded(
                              child: BlocProvider<BeaconLobbyCubit>(
                                create: (_) => cubit,
                                child: const BeaconLobbyChat(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              await tester.pump();
              await tester.runAsync(() async {
                await tester.tap(find.text('Show error'));
                await drain('ui-control-$sequence');
              });
              await tester.pumpAndSettle();
              expect(find.text(expected, findRichText: true), findsOneWidget);
              if (cubit != null) {
                expect(port!.calls, contains('access'));
                final denial = find.byKey(const Key('beaconLobbyUnavailable'));
                expect(
                  denial,
                  findsOneWidget,
                );
                // Questions uses its own translated denial surface, whereas
                // the 1102 room error above uses the generic access error bar.
                expect(
                  find.descendant(
                    of: denial,
                    matching: find.text(
                      locale == 'en'
                          ? 'Questions are for the people this request was sent to.'
                          : 'Вопросы доступны тем, кому отправлен этот запрос.',
                      findRichText: true,
                    ),
                  ),
                  findsOneWidget,
                );
                expect(
                  find.textContaining('beaconLobbyAccessDenied'),
                  findsNothing,
                );
                // Let BlocProvider dispose the Questions cubit and subscriptions.
                await tester.pumpWidget(const SizedBox.shrink());
              }
              return transport.events
                  .skip(before)
                  .where(
                    (event) =>
                        !event.throwable.toString().contains('ui-control-'),
                  )
                  .toList();
            }

            const unknownWire = GraphQLError(
              message: 'Unexpected storage failure',
              extensions: {'code': '1999'},
            );
            final unknown = mapRemoteFailure(unknownWire);
            final unknownEvents = await show(
              unknown,
              unknownWire.message,
              diagnostics: includeDiagnostics
                  ? [const GraphQLException(label: 'save', error: unknownWire)]
                  : const [],
            );
            expect(unknownEvents, hasLength(includeDiagnostics ? 2 : 1));
            expect(unknownEvents.first.throwable, same(unknown));

            for (final row in _cases) {
              final wire = GraphQLError(
                message: row.message,
                extensions: {
                  'code': row.code,
                  if (row.code == '1704') 'retryAfterMs': 2400,
                },
              );
              final error = mapRemoteFailure(wire);
              if (row.code == '1704') {
                expect(
                  error,
                  isA<RemoteApiRetryLaterException>().having(
                    (e) => e.retryAfter.inMilliseconds,
                    'backoff',
                    2400,
                  ),
                );
              }
              final events = await show(
                error,
                locale == 'en' ? row.en : row.ru,
                wire: wire,
                diagnostics: includeDiagnostics
                    ? [
                        // Preserve code and retryAfterMs inside the real wrapper,
                        // alongside the legacy message-only representation.
                        GraphQLException(label: 'save', error: wire),
                        GraphQLException(label: 'save', error: row.message),
                      ]
                    : const [],
              );
              if (events.isNotEmpty) leaked.add('${row.code}: ${row.message}');
            }
            const timeout = RequestTimeoutException();
            const timeoutText =
                'The server took too long to answer. It may still have gone through.';
            final timeoutEvents = await show(
              timeout,
              locale == 'en'
                  ? timeoutText
                  : 'Сервер слишком долго не отвечал. Возможно, действие всё же выполнено.',
              diagnostics: includeDiagnostics
                  ? [const RemoteApiException(timeoutText)]
                  : const [],
              messageDiagnostic: includeDiagnostics ? timeoutText : null,
            );
            if (timeoutEvents.isNotEmpty) leaked.add('user-facing timeout');
            expect(
              leaked,
              isEmpty,
              reason:
                  'Expected failures above must retain their UI without creating Sentry issues',
            );
          },
          timeout: const Timeout(Duration(seconds: 30)),
        );
      }
    }
  });
}
