// #481 (room level): in a Request room, Attach › Fact on a room with no
// pinned facts must let the member pin the first fact from right there —
// "Pin your first fact" in the picker opens the Add-fact form.
//
// The picker-only tests (issue_481_fact_picker_empty_test.dart) pass as soon
// as `showFactPickerSheet` takes `onAddFact`; this test also fails until
// beacon_room_body.dart actually passes `onAddFact` from its `onPickFact`
// call site (opening `showBeaconFactComposerSheet` with the
// `BeaconViewCubit` provided above the room, as BeaconViewScope does on the
// Request route).
//
// Fails to compile until the l10n key `beaconRoomFactPickerPinFirst` exists.
//
// PR #608 owner review (should-fix 2): the room body must not depend on
// BeaconViewCubit. It finds the Add-fact hand-off through the
// `RoomFactAuthoring` interface (beacon_threads/ui/room_fact_authoring.dart),
// which BeaconViewCubit implements and BeaconViewScope provides. So this test
// provides the cubit under that type too, and the guard test below checks a
// BeaconViewCubit alone (no RoomFactAuthoring) no longer enables the action.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/room_fact_authoring.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_initial_load_test.dart' show pumpUntil;
import 'support/room_body_harness.dart';

const _me = Profile(id: 'me', displayName: 'Me');
const _beaconId = 'B1';

Beacon _beacon() => Beacon(
  id: _beaconId,
  title: 'Facts beacon',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  author: _me,
);

/// [pumpBeaconRoomBody] (support/room_body_harness.dart) plus a loaded
/// [BeaconViewCubit] above the room, as on the Request route
/// (beacon_view_scope.dart). The viewer is the beacon author, so
/// `canCoordinateInBeaconRoom` is true and the room is writable.
///
/// [provideAuthoring]: also provide the cubit as [RoomFactAuthoring], as
/// beacon_view_scope.dart does. `RepositoryProvider` is a plain
/// `Provider<T>` (flutter_bloc does not export `Provider` itself, and
/// `provider` is not a direct dependency of the client package).
Future<void> _pumpRequestRoomWithNoFacts(
  WidgetTester tester, {
  bool provideAuthoring = true,
}) async {
  final getIt = GetIt.I;
  await getIt.reset();

  final viewCubit = (await tester.runAsync(() async {
    final c = BeaconViewCubit(
      id: _beaconId,
      myProfile: _me,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => _beacon(),
        factCardsRepo: FakeBeaconViewFactCardRepository(),
        roomRepo: FakeBeaconViewRoomRepository(),
      ),
      effects: FakeUiEffectPort(),
    );
    await pumpUntil(c.stream, () => c.state.beaconContextLoaded);
    return c;
  }))!;
  addTearDown(viewCubit.close);

  final profileCubit = RoomBodyHarnessProfileCubit(_me);
  final presenceCubit = RoomBodyHarnessPresenceCubit();
  final roomCubit = RoomBodyHarnessCubit(
    roomBodyState(beaconId: _beaconId, myUserId: _me.id),
  );

  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(ClipboardImageRepository());

  const width = 390.0;
  const height = 812.0;
  await tester.binding.setSurfaceSize(const Size(width, height));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<BeaconViewCubit>.value(value: viewCubit),
        if (provideAuthoring)
          RepositoryProvider<RoomFactAuthoring>.value(value: viewCubit),
        BlocProvider<RoomCubit>.value(value: roomCubit),
        BlocProvider<ProfileCubit>.value(value: profileCubit),
        BlocProvider<PresenceCubit>.value(value: presenceCubit),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(size: Size(width, height)),
          child: TenturaResponsiveScope(
            child: Scaffold(body: BeaconRoomBody()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    '#481 room: Attach › Fact › Pin your first fact opens the Add-fact form',
    (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      await _pumpRequestRoomWithNoFacts(tester);

      await tester.tap(find.byKey(const ValueKey('attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.beaconRoomAttachPickFact));
      await tester.pumpAndSettle();
      expect(find.byType(FactPickerSheet), findsOneWidget);

      final pinFirst = find.descendant(
        of: find.byType(FactPickerSheet),
        matching: find.text(l10n.beaconRoomFactPickerPinFirst),
      );
      expect(
        pinFirst,
        findsOneWidget,
        reason:
            'beacon_room_body.dart must pass onAddFact to showFactPickerSheet '
            'when a BeaconViewCubit is available and the viewer may add facts '
            '— otherwise the empty picker in the room is still a dead end',
      );

      await tester.tap(pinFirst);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(FactPickerSheet), findsNothing);
      expect(
        find.text(l10n.beaconFactsComposerTitle),
        findsOneWidget,
        reason: 'Pin your first fact must open the Add-fact form in the room',
      );
      expect(
        find.text(l10n.beaconFactsComposerPostsToDiscussion),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '#481 room: without RoomFactAuthoring the empty picker offers no '
    'Pin your first fact (body does not reach for BeaconViewCubit)',
    (tester) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      // A BeaconViewCubit is above the room, but nothing provides
      // RoomFactAuthoring (e.g. a host that does not author facts).
      await _pumpRequestRoomWithNoFacts(tester, provideAuthoring: false);

      await tester.tap(find.byKey(const ValueKey('attach')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.beaconRoomAttachPickFact));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(FactPickerSheet), findsOneWidget);
      expect(
        find.text(l10n.beaconRoomFactPickerPinFirst),
        findsNothing,
        reason:
            'beacon_room_body.dart must find the Add-fact hand-off only via '
            'context.read<RoomFactAuthoring?>(), not BeaconViewCubit',
      );
    },
  );
}
