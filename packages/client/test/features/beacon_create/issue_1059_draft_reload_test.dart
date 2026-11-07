import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/data/service/unsaved_changes_guard_impl.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/port/unsaved_changes_guard_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../support/phone_surface.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../auth/auth_test_helpers.dart';
import 'fake_beacon_ports.dart';

class _ContextRepositoryFake extends Fake implements ContextRepository {
  @override
  Stream<RepositoryEvent<ContextEntity>> get changes =>
      const Stream<RepositoryEvent<ContextEntity>>.empty();

  @override
  Future<Iterable<String>> fetch({bool fromCache = true}) async => [];
}

class _UrlRouter extends Fake implements StackRouter {
  _UrlRouter(this._url);

  String _url;
  final marks = <String>[];

  @override
  String get currentUrl => _url;

  set url(String value) => _url = value;

  @override
  void markUrlStateForReplace() => marks.add('mark');

  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => true;
}

const _savedTitle = 'Длинный заголовок черновика на русском';
const _savedDescription =
    'Описание запроса с достаточным количеством символов для автосохранения.';

Beacon _draftBeacon() => Beacon.empty.copyWith(
  id: 'draft-reload-1',
  status: BeaconStatus.draft,
  title: _savedTitle,
  description: _savedDescription,
);

Future<void> _pumpCreate(
  WidgetTester tester, {
  required BeaconCreateCubit cubit,
  required _UrlRouter router,
  String draftId = '',
  String forwardTo = '',
  String parentId = '',
  Locale locale = const Locale('ru'),
  bool phoneSurface = false,
}) async {
  if (phoneSurface) {
    await usePhoneSurface(tester);
  }
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(size: Size(375, 667)),
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
                  BlocProvider(create: (_) => ContextCubit()),
                  BlocProvider<BeaconCreateCubit>.value(value: cubit),
                ],
                child: BeaconCreateScreen(
                  draftId: draftId,
                  forwardToUserId: forwardTo,
                  parentBeaconId: parentId,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    GetIt.I
      ..registerSingleton<Env>(const Env(googleMapsApiKey: 'test-key'))
      ..registerSingleton<UiEffectPort>(FakeUiEffectPort())
      ..registerSingleton<AuthCase>(
        buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote()),
      )
      ..registerSingleton<ContextRepository>(_ContextRepositoryFake())
      ..registerSingleton<UnsavedChangesGuardPort>(UnsavedChangesGuard());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  group('issue #1059 draft reload', () {
    testWidgets(
      'autosave writes draft_id into the browser URL without navigating',
      (tester) async {
        final reports = <Map<Object?, Object?>>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          (call) async {
            if (call.method == 'routeInformationUpdated') {
              reports.add(call.arguments as Map<Object?, Object?>);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.navigation,
            null,
          ),
        );

        final write = FakeBeaconWritePort();
        final cubit = BeaconCreateCubit(
          beaconCreateCase: fakeBeaconCreateCase(write: write),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        final router = _UrlRouter(
          '$kPathBeaconNew?${kQueryBeaconForwardTo}=U-peer&${kQueryBeaconParentId}=parent-9',
        );

        await _pumpCreate(
          tester,
          cubit: cubit,
          router: router,
          forwardTo: 'U-peer',
          parentId: 'parent-9',
        );
        cubit
          ..setAutosaveContext('')
          ..setTitle(_savedTitle)
          ..setDescription(_savedDescription);
        await cubit.flushAutosave();
        await tester.pumpAndSettle();

        final draftReports = reports
            .where((r) => r['uri'].toString().contains(kQueryBeaconDraftId))
            .toList();
        expect(draftReports, isNotEmpty);
        final last = draftReports.last;
        expect(last['replace'], isTrue);
        final uri = Uri.parse(last['uri'].toString());
        expect(uri.queryParameters[kQueryBeaconDraftId], cubit.state.draftId);
        expect(uri.queryParameters[kQueryBeaconForwardTo], 'U-peer');
        expect(uri.queryParameters[kQueryBeaconParentId], 'parent-9');
        expect(router.marks, contains('mark'));
      },
    );

    testWidgets(
      'BeaconCreateRoute with draft_id restores title and description (375×667 RU)',
      (tester) async {
        final write = FakeBeaconWritePort(beacon: _draftBeacon());
        final cubit = BeaconCreateCubit(
          beaconCreateCase: fakeBeaconCreateCase(write: write),
          draftBeaconIdToLoad: 'draft-reload-1',
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        final router = _UrlRouter(
          '$kPathBeaconNew?$kQueryBeaconDraftId=draft-reload-1',
        );

        await _pumpCreate(
          tester,
          cubit: cubit,
          router: router,
          draftId: 'draft-reload-1',
          phoneSurface: true,
        );
        await tester.pumpAndSettle();

        expect(
          find.text(_savedTitle),
          findsWidgets,
          reason: 'saved title should appear in the editor',
        );
        expect(
          find.text(_savedDescription),
          findsWidgets,
          reason: 'saved description should appear in the editor',
        );
        expect(
          find.text('Редактировать черновик'),
          findsOneWidget,
          reason: 'RU locale shows edit-draft title when opened by draft_id',
        );

        final titleSize = tester.getSize(
          find.byKey(TestIds.key(TestIds.requestTitle)),
        );
        final descSize = tester.getSize(
          find.byKey(TestIds.key(TestIds.requestDescription)),
        );
        expect(titleSize.width, lessThanOrEqualTo(375));
        expect(descSize.width, lessThanOrEqualTo(375));
      },
    );

    testWidgets('hidden lifecycle flushes autosave', (tester) async {
      final write = FakeBeaconWritePort();
      final cubit = BeaconCreateCubit(
        beaconCreateCase: fakeBeaconCreateCase(write: write),
        effects: FakeUiEffectPort(),
      );
      addTearDown(cubit.close);
      final router = _UrlRouter(kPathBeaconNew);

      await _pumpCreate(tester, cubit: cubit, router: router);
      cubit
        ..setAutosaveContext('')
        ..setTitle(_savedTitle)
        ..setDescription(_savedDescription);
      await tester.pump(const Duration(milliseconds: 100));
      expect(write.createdFields, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pumpAndSettle();

      expect(write.createdFields, isNotEmpty);
      expect(cubit.state.draftId, isNotNull);
    });
  });
}
