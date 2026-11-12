// The Field's list view, opened before the Field has ever loaded and with the
// load failing, shows the same shared load-error panel as the map (title and
// body in the user's language, a «Try again» button) instead of printing the
// exception. A refresh that fails after the Field has loaded keeps the people
// on screen.
//
// Two layers:
//  - the production ConstellationCubit and ConstellationFieldStoreCase with
//    only the repository substituted, for every kind of load failure the
//    shared panel tells apart;
//  - the real transport (RemoteApiService over a MockClient, then
//    ConstellationRepository) so a failing network or a GraphQL error is what
//    reaches the view.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tentura/data/service/network_reachability.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/server_exception.dart';
import 'package:tentura/domain/port/network_reachability_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/exception.dart';
import 'package:tentura/features/constellation/data/repository/constellation_repository.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_text_view.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/screen_load_error_panel.dart';

import '../../support/constellation_store_fixture.dart';
import '../../support/people_tags_widget_harness.dart';

const _ego = Profile(id: 'ego', displayName: 'Ego');

/// The text view's old, unlocalized error line.
const _rawErrorKey = Key('constellation.text.error');

/// Fails every fetch with [error] until [error] is cleared, then serves
/// [field]. Counts fetches.
final class _FailingRepository implements ConstellationRepositoryPort {
  _FailingRepository(this.error, this.field);

  Object? error;
  final ConstellationField field;
  int fetches = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetches++;
    final failure = error;
    if (failure != null) {
      Error.throwWithStackTrace(failure, StackTrace.current);
    }
    return field;
  }
}

ConstellationField _field() => ConstellationField(
  loadedAt: DateTime.utc(2026, 11, 12, 12),
  context: '',
  peers: const [ConstellationPerson(id: 'a', displayName: 'Ann')],
  edges: const [ConstellationTrustEdgeEntity(src: 'ego', dst: 'a', tier: 1)],
  requests: const [
    ConstellationRequest(
      id: 'req-a1',
      authorId: 'a',
      title: 'Tools',
      status: 0,
    ),
  ],
);

Widget _app(ConstellationCubit cubit, Locale locale) => MaterialApp(
  locale: locale,
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: TenturaResponsiveScope(
    child: BlocProvider<ConstellationCubit>.value(
      value: cubit,
      child: const Scaffold(body: ConstellationTextView()),
    ),
  ),
);

L10n _l10n(WidgetTester tester) =>
    L10n.of(tester.element(find.byType(ConstellationTextView)))!;

/// The shared panel is on screen, carrying the description the shared
/// classifier gives [error] in the app's language, with no leftover raw line.
void _expectSharedPanelFor(WidgetTester tester, Object error) {
  final l10n = _l10n(tester);
  final expected = describeScreenLoadError(error: error, l10n: l10n);

  expect(
    find.byType(ScreenLoadErrorPanel),
    findsOneWidget,
    reason: 'a failed first load shows the shared load-error panel',
  );
  final panel = tester.widget<ScreenLoadErrorPanel>(
    find.byType(ScreenLoadErrorPanel),
  );
  expect(panel.details.kind, expected.kind);
  expect(panel.details.title, expected.title);
  expect(panel.details.message, expected.message);
  expect(find.text(expected.title), findsOneWidget);
  expect(find.text(expected.message), findsOneWidget);
  expect(find.text(l10n.myWorkRetry), findsOneWidget);
  expect(find.byKey(_rawErrorKey), findsNothing);
}

void main() {
  group('Field list view when the first load fails', () {
    late _FailingRepository repository;
    late ConstellationCubit cubit;

    Future<void> openFailedTextView(
      WidgetTester tester, {
      Locale locale = const Locale('en'),
    }) async {
      cubit = ConstellationStoreFixture(
        repository,
        accountId: 'ego',
      ).createCubit(viewer: _ego)..setViewMode(ConstellationViewMode.text);
      await tester.pumpPeopleTagsWidget(_app(cubit, locale));
      await tester.pumpAndSettle();
      await tester.runAsync(cubit.load);
      await tester.pumpAndSettle();
      expect(cubit.state.loadError, isNotNull);
      expect(cubit.state.field, isNull);
    }

    setUp(() {
      repository = _FailingRepository(
        const ConnectionUplinkException(),
        _field(),
      );
    });

    testWidgets('shows the shared «No connection» panel, not the exception', (
      tester,
    ) async {
      await openFailedTextView(tester);

      _expectSharedPanelFor(tester, const ConnectionUplinkException());
      expect(find.text('No connection'), findsOneWidget);
      expect(find.textContaining('Instance of'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('shows the shared panel in Russian when the app is Russian', (
      tester,
    ) async {
      await openFailedTextView(tester, locale: const Locale('ru'));

      _expectSharedPanelFor(tester, const ConnectionUplinkException());
      expect(find.text('Нет соединения'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
      expect(find.textContaining('Instance of'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });

    for (final (name, error, englishTitle) in <(String, Object, String)>[
      ('a lost session', const AuthSessionLostException(), 'Session problem'),
      (
        'a request that timed out',
        TimeoutException('read timed out'),
        'No connection',
      ),
      (
        'an unavailable server',
        const ServerStatusException(503),
        'Server error',
      ),
      (
        'an unknown server status',
        const ServerStatusException(418),
        'Server error',
      ),
      (
        'a missing resource',
        const ServerStatusException(404),
        'Access problem',
      ),
      (
        'a server-side GraphQL error',
        const RemoteApiException('field resolver exploded'),
        'Server error',
      ),
      (
        'an unclassified failure',
        StateError('mapper blew up'),
        "Couldn't load",
      ),
    ]) {
      testWidgets('$name is explained by the shared panel, in English', (
        tester,
      ) async {
        repository.error = error;
        await openFailedTextView(tester);

        _expectSharedPanelFor(tester, error);
        expect(find.text(englishTitle), findsOneWidget);
      });

      testWidgets('$name is explained by the shared panel, in Russian', (
        tester,
      ) async {
        repository.error = error;
        await openFailedTextView(tester, locale: const Locale('ru'));

        _expectSharedPanelFor(tester, error);
        expect(find.text(englishTitle), findsNothing);
      });
    }

    testWidgets(
      "the panel's «Try again» loads the Field and shows its people",
      (
        tester,
      ) async {
        await openFailedTextView(tester);
        final retry = find.text('Try again');
        expect(find.byType(ScreenLoadErrorPanel), findsOneWidget);
        expect(retry, findsOneWidget);
        final fetchesBeforeRetry = repository.fetches;
        repository.error = null;

        await tester.tap(retry);
        await tester.runAsync(() async {
          // The load may already have finished while the tap was dispatched.
          if (cubit.state.field != null) return;
          await cubit.stream
              .firstWhere((s) => s.field != null)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw TestFailure(
                  'Tapping "Try again" never loaded the Field',
                ),
              );
        });
        await tester.pumpAndSettle();

        expect(repository.fetches, greaterThan(fetchesBeforeRetry));
        expect(find.byType(ScreenLoadErrorPanel), findsNothing);
        expect(find.text('No connection'), findsNothing);
        expect(find.text('Ann'), findsWidgets);
      },
    );
  });

  group('Field list view when a refresh fails after the Field has loaded', () {
    testWidgets('keeps showing the people and no error panel', (tester) async {
      final repository = _FailingRepository(null, _field());
      final cubit = ConstellationStoreFixture(
        repository,
        accountId: 'ego',
      ).createCubit(viewer: _ego)..setViewMode(ConstellationViewMode.text);
      await tester.pumpPeopleTagsWidget(_app(cubit, const Locale('en')));
      await tester.pumpAndSettle();
      await tester.runAsync(cubit.load);
      await tester.pumpAndSettle();
      expect(cubit.state.field, isNotNull);
      expect(find.text('Ann'), findsWidgets);

      repository.error = const ConnectionUplinkException();
      await tester.runAsync(cubit.load);
      await tester.pumpAndSettle();

      expect(cubit.state.loadError, isNotNull);
      expect(cubit.state.field, isNotNull);
      expect(find.text('Ann'), findsWidgets);
      expect(find.byType(ScreenLoadErrorPanel), findsNothing);
      expect(find.text('No connection'), findsNothing);
      expect(find.textContaining('Instance of'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });
  });

  group('Field list view over the real transport', () {
    /// What the fake server does with the Field read.
    Future<http.Response> Function(http.Request request) failure(
      String kind,
    ) => switch (kind) {
      // The browser cannot reach the server: `fetch` rejects.
      'down' => (request) async => throw http.ClientException(
        'Failed to fetch',
        request.url,
      ),
      // The server answers with a GraphQL error.
      _ => (request) async => http.Response(
        jsonEncode({
          'data': null,
          'errors': [
            {'message': 'field resolver exploded'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    };

    http.Client client(String kind, List<String> operations) =>
        MockClient((request) async {
          if (request.url.path.endsWith('/session/access-token')) {
            return http.Response(
              jsonEncode({
                'subject': _ego.id,
                'access_token': 'test-token',
                'expires_in': 3600,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          operations.add(payload['operationName'] as String);
          return failure(kind)(request);
        });

    Future<void> openOverRealTransport(
      WidgetTester tester,
      String kind, {
      required Locale locale,
      required Future<void> Function(List<String> operations) body,
    }) {
      final operations = <String>[];
      return http.runWithClient(() async {
        final reachability = NetworkReachability.forTesting();
        GetIt.I
          ..registerSingleton<NetworkReachabilityPort>(reachability)
          ..registerSingleton<NetworkReachability>(reachability);
        final remote = RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
          reachability: reachability,
        );
        try {
          await tester.runAsync(remote.setSessionAuth);
          final cubit = ConstellationStoreFixture(
            ConstellationRepository(remote),
            accountId: _ego.id,
          ).createCubit(viewer: _ego)..setViewMode(ConstellationViewMode.text);
          await tester.pumpPeopleTagsWidget(_app(cubit, locale));
          await tester.pumpAndSettle();
          await tester.runAsync(cubit.load);
          await tester.pumpAndSettle();
          expect(operations, isNotEmpty, reason: 'the Field read went out');
          expect(cubit.state.field, isNull);
          expect(cubit.state.loadError, isNotNull);
          await body(operations);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          for (var i = 0; i < 8; i++) {
            await tester.pump();
          }
          await tester.runAsync(remote.close);
          await GetIt.I.reset();
          await reachability.dispose();
        }
      }, () => client(kind, operations));
    }

    testWidgets(
      'an unreachable server ends in the localized «No connection» panel',
      (tester) async {
        await openOverRealTransport(
          tester,
          'down',
          locale: const Locale('en'),
          body: (_) async {
            expect(find.byType(ScreenLoadErrorPanel), findsOneWidget);
            expect(find.text('No connection'), findsOneWidget);
            expect(find.text('Try again'), findsOneWidget);
            expect(find.byKey(_rawErrorKey), findsNothing);
            expect(find.textContaining('Instance of'), findsNothing);
            expect(find.textContaining('Exception'), findsNothing);
          },
        );
      },
    );

    testWidgets(
      'an unreachable server ends in the Russian «Нет соединения» panel',
      (tester) async {
        await openOverRealTransport(
          tester,
          'down',
          locale: const Locale('ru'),
          body: (_) async {
            expect(find.byType(ScreenLoadErrorPanel), findsOneWidget);
            expect(find.text('Нет соединения'), findsOneWidget);
            expect(find.text('Повторить'), findsOneWidget);
            expect(find.byKey(_rawErrorKey), findsNothing);
            expect(find.textContaining('Instance of'), findsNothing);
            expect(find.textContaining('Exception'), findsNothing);
          },
        );
      },
    );

    testWidgets(
      'a GraphQL error from the server ends in the localized «Server error» '
      'panel',
      (tester) async {
        await openOverRealTransport(
          tester,
          'graphql',
          locale: const Locale('en'),
          body: (_) async {
            expect(find.byType(ScreenLoadErrorPanel), findsOneWidget);
            expect(find.text('Server error'), findsOneWidget);
            expect(find.text('Try again'), findsOneWidget);
            expect(find.byKey(_rawErrorKey), findsNothing);
            expect(find.textContaining('Instance of'), findsNothing);
          },
        );
      },
    );
  });
}
