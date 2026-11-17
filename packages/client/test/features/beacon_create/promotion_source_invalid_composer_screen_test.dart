// The real composer screen, driven by the real transport mapping: when the
// server refuses a promotion source (code 1311) the user sees dedicated copy in
// a snackbar, the composer stays open and usable, and neither the global error
// handlers nor Sentry hear about it.

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tentura_root/domain/entity/beacon_creation_context.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/app/sentry/sentry_init.dart';
import 'package:tentura/data/service/op_id_service.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/domain/use_case/message_prefill_case.dart';
import 'package:tentura/domain/port/post_bud_port.dart';
import 'package:tentura/domain/use_case/post_bud_case.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon/domain/beacon_hierarchy_exception.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_handler.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../support/remote_wire_harness.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'child_request_send_widget_support.dart';
import 'fake_beacon_ports.dart';
import 'post_bud_fakes.dart';

const _code = 1311;
const _parentId = 'parent-1';

const _sourceResponses = <String, Map<String, dynamic>>{
  'BeaconPromotionSource': {
    '__typename': 'query_root',
    'beaconPromotionSource': {
      '__typename': 'v2_BeaconPromotionSource',
      'sourceBeaconId': _parentId,
      'sourceMessageId': 'msg-1',
      'textPreview': 'Need a ladder',
      'author': {
        '__typename': 'v2_BeaconHierarchyOwner',
        'id': 'author-1',
        'displayName': 'Alice',
        'avatarImageId': null,
      },
    },
  },
  'PostBudInviteCandidates': {
    '__typename': 'query_root',
    'postBudInviteCandidates': <Object>[],
  },
};

class _RecordingTransport implements Transport {
  final events = <SentryEvent>[];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    for (final item in envelope.items) {
      final payload = item.originalObject;
      if (payload is SentryEvent) events.add(payload);
    }
    return envelope.header.eventId;
  }
}

class _Router extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  Future<T?> push<T extends Object?>(
    PageRouteInfo route, {
    OnNavigationFailure? onFailure,
  }) async => null;
}

/// Everything a test needs to watch after the composer reported the refusal.
class _Watch {
  final flutterErrors = <FlutterErrorDetails>[];
  final platformErrors = <Object>[];
  final transport = _RecordingTransport();
  late final FlutterExceptionHandler? _oldFlutter;
  late final bool Function(Object, StackTrace)? _oldPlatform;

  Future<void> start(WidgetTester tester) async {
    final options = SentryFlutterOptions();
    configureSentryOptions(options);
    options
      ..dsn = 'https://public@example.invalid/1'
      ..transport = transport
      ..tracesSampleRate = 0
      ..enableLogs = false;
    // `options:` is the only way to hand Sentry.init a SentryFlutterOptions.
    // ignore: invalid_use_of_internal_member
    await Sentry.init((_) {}, options: options);
    _oldFlutter = FlutterError.onError;
    _oldPlatform = PlatformDispatcher.instance.onError;
    FlutterError.onError = flutterErrors.add;
    PlatformDispatcher.instance.onError = (error, stack) {
      platformErrors.add(error);
      return true;
    };
  }

  /// Lets Sentry deliver, then restores the handlers so expects can fail.
  Future<void> stop(WidgetTester tester) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await Sentry.close();
    FlutterError.onError = _oldFlutter;
    PlatformDispatcher.instance.onError = _oldPlatform;
  }
}

String _snackText(WidgetTester tester) {
  final snack = find.byType(SnackBar);
  expect(snack, findsOneWidget, reason: 'an error snackbar must be shown');
  return tester
      .widgetList<RichText>(
        find.descendant(of: snack, matching: find.byType(RichText)),
      )
      .map((t) => t.text.toPlainText())
      .join(' ');
}

Future<void> _expectHandledCopy(
  WidgetTester tester,
  String locale,
  _Watch watch,
  FakeUiEffectPort effects,
) async {
  final l10n = await L10n.delegate.load(Locale(locale));
  await watch.stop(tester);
  final text = _snackText(tester);

  expect(text, isNot(contains(l10n.errorGenericAction)));
  expect(text, isNot(contains('Exception')));
  // The recipients step retries the save after a failed autosave, so the same
  // refusal may be reported more than once; every report must be the typed one.
  final errors = effects.emitted
      .map((e) => (e as dynamic).error as Object)
      .toList();
  expect(errors, isNotEmpty);
  expect(errors, everyElement(isA<BeaconPromotionSourceInvalidException>()));
  final error = errors.first;
  expect(error, isA<Localizable>());
  expect(text, contains((error as Localizable).toL10n(locale)));
  expect(find.byType(BeaconCreateScreen), findsOneWidget);
  expect(watch.flutterErrors, isEmpty);
  expect(watch.platformErrors, isEmpty);
  expect(watch.transport.events, isEmpty, reason: 'Sentry must hear nothing');
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required String locale,
  required FakeUiEffectPort effects,
  required BeaconCreateCubit cubit,
  required Widget screen,
  required ContextCubit contextCubit,
}) async {
  const surface = Size(800, 1600);
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = _Router();
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: UiEffectHandler(
        effects: effects,
        child: MediaQuery(
          data: const MediaQueryData(size: surface),
          child: TenturaResponsiveScope(
            child: RouterScope(
              controller: router,
              stateHash: 0,
              inheritableObserversBuilder: () => const [],
              child: StackRouterScope(
                controller: router,
                stateHash: 0,
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider.value(value: contextCubit),
                    BlocProvider<ProfileCubit>.value(
                      value: GetIt.I<ProfileCubit>(),
                    ),
                    BlocProvider<BeaconCreateCubit>.value(value: cubit),
                  ],
                  child: screen,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  for (final locale in ['en', 'ru']) {
    group('composer screen after a refused promotion source ($locale)', () {
      testWidgets('saving a child draft from a message shows handled copy and '
          'keeps the composer open', (tester) async {
        final effects = FakeUiEffectPort();
        final contextCubit = await registerChildSendCollaborators();
        addTearDown(contextCubit.close);
        await GetIt.I.unregister<UiEffectPort>();
        GetIt.I.registerSingleton<UiEffectPort>(effects);
        final watch = _Watch();

        await _withWire(
          tester,
          _sourceResponses,
          {'BeaconChildCreate': wireCodeError(_code)},
          (remote) async {
            await watch.start(tester);
            final write = FakeBeaconWritePort();
            final createCase = BeaconCreateCase(write, FakeBeaconImagePort());
            final cubit = BeaconCreateCubit(
              beaconCreateCase: createCase,
              hierarchyCase: buildBeaconHierarchyCaseForTest(
                BeaconHierarchyRepository(remote),
                createCase: createCase,
                beacons: write,
                commandStore: InMemoryBeaconChildCommandStore(),
              ),
              messagePrefillCase: MessagePrefillCase(
                BeaconHierarchyRepository(remote),
              ),
              postBuddingEnabled: false,
              childCreationContext: const BeaconCreationContextPromotedChild(
                parentBeaconId: _parentId,
                sourceMessageId: 'msg-1',
              ),
              effects: effects,
            );
            addTearDown(cubit.close);
            if (cubit.state.clientCommandId == null) {
              await cubit.stream.firstWhere((s) => s.clientCommandId != null);
            }
            cubit
              ..setTitle('Need a ladder')
              ..setDescription('For Saturday.');
            await _pumpApp(
              tester,
              locale: locale,
              effects: effects,
              cubit: cubit,
              contextCubit: contextCubit,
              screen: const BeaconCreateScreen(
                parentBeaconId: _parentId,
                sourceMessageId: 'msg-1',
              ),
            );

            // The Recipients step saves the draft first.
            await tester.tap(
              find.byKey(TestIds.key(TestIds.requestRecipientsTab)),
            );
            await _settle(tester);

            await _expectHandledCopy(tester, locale, watch, effects);
            expect(cubit.state.status, isA<StateIsSuccess>());
          },
        );
      });

      testWidgets('budding from a Post shows handled copy and keeps the '
          'composer open', (tester) async {
        final effects = FakeUiEffectPort();
        final contextCubit = await registerChildSendCollaborators();
        addTearDown(contextCubit.close);
        await GetIt.I.unregister<UiEffectPort>();
        GetIt.I.registerSingleton<UiEffectPort>(effects);
        final watch = _Watch();

        await _withWire(
          tester,
          _sourceResponses,
          {'PostBudFromPost': wireCodeError(_code)},
          (remote) async {
            await watch.start(tester);
            // The invite step loads the Post's members through ForwardCase.
            GetIt.I.registerSingleton<PostBudPort>(PostBudRepository(remote));
            final h = BudHarness();
            final createCase = h.createCase;
            final cubit = BeaconCreateCubit(
              beaconCreateCase: createCase,
              hierarchyCase: buildBeaconHierarchyCaseForTest(
                h.hierarchy,
                createCase: createCase,
                beacons: h.write,
                commandStore: InMemoryBeaconChildCommandStore(),
              ),
              messagePrefillCase: h.prefillCase,
              postBudCase: PostBudCase(
                PostBudRepository(remote),
                OpIdService(),
                env: const Env(),
                logger: GetIt.I<Logger>(),
              ),
              childCreationContext: kBudContext,
              effects: effects,
            );
            addTearDown(cubit.close);
            if (cubit.state.postBud == null) {
              await cubit.stream.firstWhere((s) => s.postBud != null);
            }
            // Let the bud form's own Post reads settle.
            await Future<void>.delayed(const Duration(milliseconds: 50));
            cubit
              ..setTitle('Need a ladder')
              ..setDescription('For Saturday.');
            await _pumpApp(
              tester,
              locale: locale,
              effects: effects,
              cubit: cubit,
              contextCubit: contextCubit,
              screen: const BeaconCreateScreen(
                parentBeaconId: kBudPostId,
                sourceMessageId: kBudSourceMessageId,
              ),
            );

            await tester.tap(find.byKey(const Key('PostBud.NextButton')));
            await _settle(tester);
            await tester.tap(find.byKey(const Key('PostBud.SubmitButton')));
            await _settle(tester);

            await _expectHandledCopy(tester, locale, watch, effects);
            expect(cubit.state.status, isA<StateIsSuccess>());
          },
        );
      });
    });
  }
}

/// Runs [body] against a real [RemoteApiService] whose HTTP transport answers
/// from [responses] / [errors] (same wire as `withRemoteWire`). The whole body,
/// widget pumps included, runs in real async inside the HTTP-client zone, so
/// requests triggered by taps also reach the fake transport.
Future<void> _withWire(
  WidgetTester tester,
  Map<String, Map<String, dynamic>> responses,
  Map<String, Map<String, dynamic>> errors,
  Future<void> Function(RemoteApiService remote) body,
) async {
  await tester.runAsync(
    () => http.runWithClient(
      () async {
        final remote = RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
        );
        try {
          await remote.setSessionAuth();
          await body(remote);
        } finally {
          await remote.close();
        }
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/session/access-token')) {
          return http.Response(
            jsonEncode({
              'subject': 'Uviewer000001',
              'access_token': 'test-token',
              'expires_in': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        final json = jsonDecode(request.body) as Map<String, dynamic>;
        final name = json['operationName'] as String;
        final error = errors[name];
        return http.Response(
          jsonEncode(
            error != null
                ? {
                    'data': null,
                    'errors': [error],
                  }
                : {'data': responses[name]},
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
  );
}
