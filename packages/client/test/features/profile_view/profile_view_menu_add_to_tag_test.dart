import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/features/profile_view/ui/widget/profile_view_app_bar.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/add_to_tag_sheet_probe.dart';
import '../../support/fake_people_tags_repository.dart';
import '../../support/optional_gate_call.dart';

const _viewer = Profile(id: 'U-viewer', displayName: 'Viewer');
const _peer = Profile(id: 'U-peer', displayName: 'Peer');

class _Router extends Mock implements StackRouter {
  @override
  PagelessRoutesObserver get pagelessRoutesObserver => PagelessRoutesObserver();

  @override
  bool canPop({
    bool ignoreChildRoutes = false,
    bool ignoreParentRoutes = false,
    bool ignorePagelessRoutes = false,
  }) => false;
}

class _FakeProfileViewCubit extends Cubit<ProfileViewState>
    implements ProfileViewCubit {
  _FakeProfileViewCubit(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileCubit implements ProfileCubit {
  _FakeProfileCubit(Profile profile) : _state = ProfileState(profile: profile);

  final ProfileState _state;

  @override
  ProfileState get state => _state;

  @override
  Stream<ProfileState> get stream => Stream.value(_state);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late PeopleTagsTestRig rig;

  setUp(() async {
    rig = await PeopleTagsTestRig.create(addToTagProbeRepository(_peer.id));
    GetIt.I
      ..registerSingleton<PeopleTagsCase>(rig.peopleTags)
      ..registerSingleton<ProfileCubit>(_FakeProfileCubit(_viewer));
  });

  tearDown(() async {
    await GetIt.I.reset();
    await rig.dispose();
  });

  /// Pumps the real profile app bar for [subject] and opens its overflow menu.
  /// A null [peopleTagsEnabled] leaves the app bar's own default (the gate).
  Future<void> pumpAppBarAndOpenMenu(
    WidgetTester tester, {
    required Profile subject,
    bool? peopleTagsEnabled,
  }) async {
    final cubit = _FakeProfileViewCubit(ProfileViewState(profile: subject));
    final screenCubit = ScreenCubit.local();
    final router = _Router();
    addTearDown(cubit.close);
    addTearDown(screenCubit.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: RouterScope(
          controller: router,
          stateHash: 0,
          inheritableObserversBuilder: () => const [],
          child: StackRouterScope(
            controller: router,
            stateHash: 0,
            child: TenturaResponsiveScope(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<ProfileViewCubit>.value(value: cubit),
                  BlocProvider<ScreenCubit>.value(value: screenCubit),
                ],
                child: Builder(
                  builder: (context) => Scaffold(
                    appBar:
                        callWithPeopleTagsGate(
                              buildProfileViewAppBar,
                              gate: peopleTagsEnabled,
                              positional: [context],
                            )
                            as PreferredSizeWidget,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
  }

  /// Pumps a button that opens the menu built by [profileViewPopupMenuEntries]
  /// for [subject], and opens it. A null [peopleTagsEnabled] leaves the
  /// entries' own default (the gate).
  Future<void> pumpEntriesAndOpenMenu(
    WidgetTester tester, {
    required Profile subject,
    bool? peopleTagsEnabled,
  }) async {
    final cubit = _FakeProfileViewCubit(ProfileViewState(profile: subject));
    final screenCubit = ScreenCubit.local();
    addTearDown(cubit.close);
    addTearDown(screenCubit.close);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TenturaResponsiveScope(
          child: Builder(
            builder: (context) => Scaffold(
              body: PopupMenuButton<void>(
                itemBuilder: (menuContext) =>
                    (callWithPeopleTagsGate(
                              profileViewPopupMenuEntries,
                              gate: peopleTagsEnabled,
                              named: {
                                #context: context,
                                #state: cubit.state,
                                #viewerId: _viewer.id,
                                #l10n: L10n.of(context)!,
                                #profileViewCubit: cubit,
                                #screenCubit: screenCubit,
                              },
                            )
                            as List)
                        .cast<PopupMenuEntry<void>>(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
  }

  group('profile app bar menu: add to tag', () {
    testWidgets('offers "Add to tag…" on another person', (tester) async {
      await pumpAppBarAndOpenMenu(
        tester,
        subject: _peer,
        peopleTagsEnabled: true,
      );

      expect(find.text('Add to tag…'), findsOneWidget);
    });

    testWidgets('"Add to tag…" opens the sheet for the person on the profile', (
      tester,
    ) async {
      await pumpAppBarAndOpenMenu(
        tester,
        subject: _peer,
        peopleTagsEnabled: true,
      );

      await tester.tap(find.text('Add to tag…'));

      await expectAddToTagSheetIsForPerson(tester, rig.repository, _peer.id);
    });

    testWidgets('is not offered on the viewer own profile', (tester) async {
      await pumpAppBarAndOpenMenu(
        tester,
        subject: _viewer,
        peopleTagsEnabled: true,
      );

      expect(find.text('Add to tag…'), findsNothing);
    });

    testWidgets('is not offered when the feature is switched off', (
      tester,
    ) async {
      await pumpAppBarAndOpenMenu(
        tester,
        subject: _peer,
        peopleTagsEnabled: false,
      );

      expect(find.text('Add to tag…'), findsNothing);
    });

    testWidgets('is not offered by default while the feature gate is off', (
      tester,
    ) async {
      await pumpAppBarAndOpenMenu(tester, subject: _peer);

      expect(find.text('Add to tag…'), findsNothing);
    });
  });

  group('profile popup menu entries: add to tag', () {
    testWidgets('offers "Add to tag…" on another person and opens the sheet '
        'for that person', (tester) async {
      await pumpEntriesAndOpenMenu(
        tester,
        subject: _peer,
        peopleTagsEnabled: true,
      );
      expect(find.text('Add to tag…'), findsOneWidget);

      await tester.tap(find.text('Add to tag…'));

      await expectAddToTagSheetIsForPerson(tester, rig.repository, _peer.id);
    });

    testWidgets('does not offer it on the viewer own profile', (tester) async {
      await pumpEntriesAndOpenMenu(
        tester,
        subject: _viewer,
        peopleTagsEnabled: true,
      );

      expect(find.text('Add to tag…'), findsNothing);
    });

    testWidgets('does not offer it when the feature is switched off', (
      tester,
    ) async {
      await pumpEntriesAndOpenMenu(
        tester,
        subject: _peer,
        peopleTagsEnabled: false,
      );

      expect(find.text('Add to tag…'), findsNothing);
    });
  });
}
