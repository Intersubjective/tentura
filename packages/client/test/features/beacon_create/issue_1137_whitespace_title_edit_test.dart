import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_cubit.dart';
import 'package:tentura/features/beacon_create/ui/bloc/beacon_create_state.dart';
import 'package:tentura/features/beacon_create/ui/screen/beacon_create_screen.dart';
import 'package:tentura/features/context/data/repository/context_repository.dart';
import 'package:tentura/features/context/domain/entity/context_entity.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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

Finder _editSaveButton() => find.byKey(const Key('BeaconEdit.SaveChangesButton'));

Widget _editScreenHarness({
  required BeaconCreateCubit cubit,
  required ContextCubit contextCubit,
  Locale locale = const Locale('en'),
}) {
  final router = _NavRouter();
  return MaterialApp(
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
                BlocProvider<ContextCubit>.value(value: contextCubit),
                BlocProvider<BeaconCreateCubit>.value(value: cubit),
              ],
              child: const BeaconCreateScreen(editId: 'b-edit'),
            ),
          ),
        ),
      ),
    ),
  );
}

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

  BeaconCreateCubit _loadedCubit(FakeBeaconWritePort write) {
    return BeaconCreateCubit(
      beaconCreateCase: fakeBeaconCreateCase(write: write),
      effects: FakeUiEffectPort(),
      editBeaconIdToLoad: 'b-edit',
    );
  }

  test('editSaveBlocker rejects whitespace-only title (#1137)', () {
    const state = BeaconCreateState(
      editId: 'b-edit',
      title: '   ',
      description: 'Body text here.',
    );
    expect(state.editSaveBlocker, BeaconPublishBlocker.title);
  });

  test('saveEdit does not call update when title is whitespace only (#1137)', () async {
    final write = FakeBeaconWritePort(
      beacon: Beacon.empty.copyWith(
        id: 'b-edit',
        status: BeaconStatus.open,
        title: 'Valid title',
        description: 'Old body',
        author: const Profile(id: 'author-1'),
      ),
    );
    final cubit = _loadedCubit(write);
    await cubit.stream.firstWhere((s) => s.editId == 'b-edit');
    cubit.setTitle('   ');
    await cubit.saveEdit(context: 'Life');
    expect(write.updatedFields, isEmpty);
    expect(cubit.state.showValidationHints, isTrue);
    await cubit.close();
  });

  test('saveEdit trims title on the wire (#1137)', () async {
    final write = FakeBeaconWritePort(
      beacon: Beacon.empty.copyWith(
        id: 'b-edit',
        status: BeaconStatus.open,
        title: 'Valid title',
        description: 'Old body',
        author: const Profile(id: 'author-1'),
      ),
    );
    final cubit = _loadedCubit(write);
    await cubit.stream.firstWhere((s) => s.editId == 'b-edit');
    cubit.setTitle('  Need help  ');
    await cubit.saveEdit(context: 'Life');
    expect(write.updatedFields, hasLength(1));
    expect(write.updatedFields.single.title, 'Need help');
    await cubit.close();
  });

  testWidgets('whitespace-only title disables Save changes at 375 RU (#1137)', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final l10n = lookupL10n(const Locale('ru'));
    final write = FakeBeaconWritePort(
      beacon: Beacon.empty.copyWith(
        id: 'b-edit',
        status: BeaconStatus.open,
        title: 'Valid title',
        description: 'Old body',
        author: const Profile(id: 'author-1'),
      ),
    );
    final cubit = _loadedCubit(write);
    await cubit.stream.firstWhere((s) => s.editId == 'b-edit');
    addTearDown(cubit.close);

    await tester.pumpWidget(
      _editScreenHarness(
        cubit: cubit,
        contextCubit: contextCubit,
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();

    final titleField = find.byKey(TestIds.key(TestIds.requestTitle));
    await tester.enterText(titleField, '   ');
    await tester.pump();

    final button = tester.widget<FilledButton>(_editSaveButton());
    expect(button.onPressed, isNull);
    expect(find.text(l10n.titleTooShort), findsWidgets);
    expect(write.updatedFields, isEmpty);
  });
}
