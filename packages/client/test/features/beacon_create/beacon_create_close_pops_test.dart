import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../auth/auth_test_helpers.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'fake_beacon_ports.dart';

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

/// Cap [maybePop] so a [PopScope] re-entry loop fails the assertion instead
/// of hanging the test's microtask queue.
class _NavRouter extends Mock implements StackRouter {
  late BuildContext host;
  int maybePopCalls = 0;

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  /// Stack-depth check only. [Navigator.canPop] is false under
  /// [PopScope.canPop] `false`; AutoRoute still reports a poppable stack.
  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;

  @override
  Future<bool> maybePop<T extends Object?>([T? result]) async {
    maybePopCalls++;
    if (maybePopCalls > 3) return false;
    return Navigator.of(host).maybePop(result);
  }
}

void main() {
  late BeaconCreateCubit createCubit;
  late ContextCubit contextCubit;

  setUp(() {
    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
    createCubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(),
      effects: FakeUiEffectPort(),
    );
    contextCubit = ContextCubit(
      authCase: buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
      contextRepository: _ContextRepositoryFake(),
      effects: FakeUiEffectPort(),
    );
  });

  tearDown(() async {
    await createCubit.close();
    await contextCubit.close();
    await GetIt.I.reset();
  });

  testWidgets('close control pops the create route', (tester) async {
    final router = _NavRouter();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (homeContext) {
            return TextButton(
              onPressed: () {
                Navigator.of(homeContext).push<void>(
                  MaterialPageRoute<void>(
                    builder: (routeContext) {
                      router.host = routeContext;
                      return RouterScope(
                        controller: router,
                        stateHash: 0,
                        inheritableObserversBuilder: () => const [],
                        child: StackRouterScope(
                          controller: router,
                          stateHash: 0,
                          child: MultiBlocProvider(
                            providers: [
                              BlocProvider<ContextCubit>.value(
                                value: contextCubit,
                              ),
                              BlocProvider<BeaconCreateCubit>.value(
                                value: createCubit,
                              ),
                            ],
                            child: const BeaconCreateScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
              child: const Text('open-create'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open-create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(BeaconCreateScreen), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(TenturaTopBar),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(BeaconCreateScreen), findsNothing);
    expect(find.text('open-create'), findsOneWidget);
  });
}
