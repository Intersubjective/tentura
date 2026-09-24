import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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

/// Holds [FakeBeaconWritePort.update] until [release] completes.
class _SlowEditWritePort extends FakeBeaconWritePort {
  _SlowEditWritePort({
    required this.release,
    required Beacon beacon,
  }) : super(beacon: beacon);

  final Completer<void> release;
  var updateCalls = 0;

  @override
  Future<Beacon> update(Beacon fields) async {
    updateCalls++;
    await release.future;
    return super.update(fields);
  }
}

Finder _editSaveButton() => find.byKey(const Key('BeaconEdit.SaveChangesButton'));

class _NavRouter extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) =>
      false;
}

Widget _editScreenHarness({
  required BeaconCreateCubit cubit,
  required ContextCubit contextCubit,
}) {
  final router = _NavRouter();
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    theme: TenturaTheme.light(),
    home: MediaQuery(
      data: const MediaQueryData(size: Size(1200, 1200)),
      child: RouterScope(
        controller: router,
        stateHash: 0,
        inheritableObserversBuilder: () => const [],
        child: StackRouterScope(
          controller: router,
          stateHash: 0,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ContextCubit>.value(value: contextCubit),
              BlocProvider<BeaconCreateCubit>.value(value: cubit),
            ],
            child: const BeaconCreateScreen(editId: 'b-edit'),
          ),
        ),
      ),
    ),
  );
}

/// GitHub #174 — edit-request actions must acknowledge taps immediately
/// (disabled control + visible progress while slow saves run).
void main() {
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

  Future<BeaconCreateCubit> _loadedEditCubit(_SlowEditWritePort write) async {
    final cubit = BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      effects: FakeUiEffectPort(),
      editBeaconIdToLoad: 'b-edit',
    );
    await cubit.stream.firstWhere((s) => s.editId == 'b-edit');
    cubit
      ..setTitle('Need help moving furniture')
      ..setDescription('Two flights of stairs, this weekend.');
    return cubit;
  }

  testWidgets(
    'issue #174 save changes shows in-button progress while update is slow',
    (tester) async {
      final hold = Completer<void>();
      final write = _SlowEditWritePort(
        release: hold,
        beacon: Beacon.empty.copyWith(
          id: 'b-edit',
          status: BeaconStatus.open,
          title: 'Old title',
          description: 'Old body',
          author: const Profile(id: 'author-1'),
        ),
      );
      final cubit = await _loadedEditCubit(write);
      addTearDown(cubit.close);

      await tester.pumpWidget(
        _editScreenHarness(cubit: cubit, contextCubit: contextCubit),
      );
      await tester.pumpAndSettle();

      await tester.tap(_editSaveButton());
      await tester.pump();

      expect(cubit.state.isLoading, isTrue);
      expect(
        find.descendant(
          of: _editSaveButton(),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
        reason:
            'Slow save must show a spinner on Save Changes, not only disable '
            'the button silently',
      );

      hold.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'issue #174 save changes disables before a second tap can start another save',
    (tester) async {
      final hold = Completer<void>();
      final write = _SlowEditWritePort(
        release: hold,
        beacon: Beacon.empty.copyWith(
          id: 'b-edit',
          status: BeaconStatus.open,
          title: 'Old title',
          description: 'Old body',
          author: const Profile(id: 'author-1'),
        ),
      );
      final cubit = await _loadedEditCubit(write);
      addTearDown(cubit.close);

      await tester.pumpWidget(
        _editScreenHarness(cubit: cubit, contextCubit: contextCubit),
      );
      await tester.pumpAndSettle();

      await tester.tap(_editSaveButton());
      await tester.tap(_editSaveButton());
      await tester.pump();

      expect(
        write.updateCalls,
        1,
        reason:
            'A second tap while the first save is in flight must not start '
            'another update (double-submit)',
      );

      hold.complete();
      await tester.pumpAndSettle();
      expect(write.updatedFields, hasLength(1));
    },
  );
}
