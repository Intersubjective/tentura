import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
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
import 'fork_beacon_ports.dart';

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

/// Cap [maybePop] so a [PopScope] re-entry loop fails the assertion instead
/// of hanging the test.
class _NavRouter extends Mock implements StackRouter {
  late BuildContext host;
  int maybePopCalls = 0;

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

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

final _source = Beacon.empty.copyWith(
  id: 'src',
  title: 'Pick up a parcel',
  description: 'At the post office on Main St, before 6 pm.',
  status: BeaconStatus.open,
);

const _banner = 'Copied from ‘Pick up a parcel’';

void main() {
  final en = lookupL10n(const Locale('en'));
  final ru = lookupL10n(const Locale('ru'));
  late ContextCubit contextCubit;

  setUp(() {
    GetIt.I.registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'));
    contextCubit = ContextCubit(
      authCase: buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
      contextRepository: _ContextRepositoryFake(),
      effects: FakeUiEffectPort(),
    );
  });

  tearDown(() async {
    await contextCubit.close();
    await GetIt.I.reset();
  });

  Future<void> openEditor(
    WidgetTester tester,
    BeaconCreateCubit createCubit,
  ) async {
    final router = _NavRouter();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: TenturaTheme.light(),
        home: Builder(
          builder: (homeContext) => TextButton(
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
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-create'));
    await tester.pumpAndSettle();
    expect(find.byType(BeaconCreateScreen), findsOneWidget);
  }

  group('#493 copy editor', () {
    test('copy strings exist in every locale', () {
      expect(
        en.beaconCopyOfTitle('Pick up a parcel'),
        'Copy of Pick up a parcel',
      );
      expect(en.beaconCopiedFromBanner('Pick up a parcel'), _banner);
      for (final s in [
        ru.beaconCopyOfTitle('Pick up a parcel'),
        ru.beaconCopiedFromBanner('Pick up a parcel'),
      ]) {
        expect(s, contains('Pick up a parcel'));
      }
      expect(
        ru.beaconCopyOfTitle('X'),
        isNot(en.beaconCopyOfTitle('X')),
      );
      expect(
        ru.beaconCopiedFromBanner('X'),
        isNot(en.beaconCopiedFromBanner('X')),
      );
    });

    testWidgets('shows Copy of title and the copied-from banner', (
      tester,
    ) async {
      final write = ForkingBeaconWritePort(source: _source);
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: FakeUiEffectPort(),
        forkSourceIdToLoad: 'src',
        forkTitle: en.beaconCopyOfTitle,
      );
      addTearDown(cubit.close);

      await openEditor(tester, cubit);

      expect(find.text(_banner, findRichText: true), findsOneWidget);
      expect(find.text('Copy of Pick up a parcel'), findsWidgets);
      expect(write.forkCalls, isEmpty);
      expect(write.createdFields, isEmpty);
    });

    testWidgets('Back from an untouched copy leaves without a draft', (
      tester,
    ) async {
      final write = ForkingBeaconWritePort(source: _source);
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: FakeUiEffectPort(),
        forkSourceIdToLoad: 'src',
        forkTitle: en.beaconCopyOfTitle,
      );
      addTearDown(cubit.close);

      await openEditor(tester, cubit);
      await tester.tap(
        find.descendant(
          of: find.byType(TenturaTopBar),
          matching: find.byIcon(Icons.arrow_back),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing was saved, so there is no Keep draft / Discard question.
      expect(find.text(en.beaconCreateLeaveTitle), findsNothing);
      expect(find.byType(BeaconCreateScreen), findsNothing);
      expect(write.forkCalls, isEmpty);
      expect(write.createdFields, isEmpty);
      expect(write.updatedDraftFields, isEmpty);
      expect(cubit.state.draftId, isNull);
    });

    testWidgets('a new request shows no copied-from banner', (tester) async {
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);

      await openEditor(tester, cubit);

      expect(
        find.textContaining('Copied from', findRichText: true),
        findsNothing,
      );
    });
  });
}
