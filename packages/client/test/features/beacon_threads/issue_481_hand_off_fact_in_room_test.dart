// #481: a fact pinned through the hand-off (Attach › Fact › "Pin your first
// fact" › the Add-fact form) shows in the room's fact cards right away: the
// room re-reads its facts when the form closes instead of waiting for a
// realtime echo of the viewer's own pin.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/room_fact_authoring.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/presence_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../beacon_view/beacon_view_initial_load_test.dart' show pumpUntil;
import 'support/room_body_harness.dart';

const _me = Profile(id: 'me', displayName: 'Me');
const _beaconId = 'B1';
const _factText = 'Door code 4711';

Beacon _beacon() => Beacon(
  id: _beaconId,
  title: 'Facts beacon',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  author: _me,
);

/// The server's fact list for the beacon: a pin adds an active card.
class _ServerFactCards extends FakeBeaconViewFactCardRepository {
  @override
  Future<void> pin({
    required String beaconId,
    required String factText,
    required int visibility,
    String? sourceMessageId,
  }) async {
    await super.pin(
      beaconId: beaconId,
      factText: factText,
      visibility: visibility,
      sourceMessageId: sourceMessageId,
    );
    cards = [
      ...cards,
      BeaconFactCard(
        id: 'fact-${cards.length + 1}',
        beaconId: beaconId,
        factText: factText,
        visibility: visibility,
        pinnedBy: _me.id,
        createdAt: DateTime.utc(2026, 10, 24),
        status: 0,
        sourceMessageId: sourceMessageId,
      ),
    ];
  }
}

/// The room's cubit: no realtime echo ever arrives; a fact-list refresh
/// reads the server's list, as RoomCubit.refreshFactCards does.
class _RoomCubit extends RoomBodyHarnessCubit {
  _RoomCubit(super.initial, this.server);

  final _ServerFactCards server;
  var refreshes = 0;

  @override
  Future<void> refreshFactCards() async {
    refreshes++;
    final cards = await server.list(beaconId: _beaconId);
    emitHarnessState(state.copyWith(factCards: cards));
  }
}

Future<void> _openFactPicker(WidgetTester tester, L10n l10n) async {
  await tester.tap(find.byKey(const ValueKey('attach')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.beaconRoomAttachPickFact));
  await tester.pumpAndSettle();
  expect(find.byType(FactPickerSheet), findsOneWidget);
}

/// The Request room over a loaded [BeaconViewCubit] that authors facts
/// against [server], with no facts pinned yet.
Future<_RoomCubit> _pumpRoom(
  WidgetTester tester,
  _ServerFactCards server,
) async {
  final getIt = GetIt.I;
  await getIt.reset();

  final viewCubit = (await tester.runAsync(() async {
    final c = BeaconViewCubit(
      id: _beaconId,
      myProfile: _me,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: TrackingBeaconRepository()
          ..fetchByIdHandler = (_) async => _beacon(),
        factCardsRepo: server,
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
  final roomCubit = _RoomCubit(
    roomBodyState(beaconId: _beaconId, myUserId: _me.id),
    server,
  );

  getIt
    ..registerSingleton<ProfileCubit>(profileCubit)
    ..registerSingleton<ImageRepository>(ImageRepository())
    ..registerSingleton<ClipboardImageRepository>(
      ClipboardImageRepository(),
    );

  const size = Size(390, 812);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<BeaconViewCubit>.value(value: viewCubit),
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
          data: MediaQueryData(size: size),
          child: TenturaResponsiveScope(
            child: Scaffold(body: BeaconRoomBody()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  return roomCubit;
}

/// Attach › Fact › "Pin your first fact" opens the Add-fact form.
Future<void> _openAddFactForm(WidgetTester tester, L10n l10n) async {
  await _openFactPicker(tester, l10n);
  await tester.tap(find.text(l10n.beaconRoomFactPickerPinFirst));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text(l10n.beaconFactsComposerTitle), findsOneWidget);
}

void main() {
  testWidgets('a fact pinned via Pin your first fact shows in the room fact '
      'cards', (tester) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    final server = _ServerFactCards();
    final roomCubit = await _pumpRoom(tester, server);

    await _openAddFactForm(tester, l10n);

    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == l10n.beaconRoomFactCardEditHint,
      ),
      _factText,
    );
    await tester.pump();
    await tester.tap(
      find.byKey(TestIds.key(TestIds.beaconFactsComposerSubmit)),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(server.pins, hasLength(1), reason: 'the form pinned the fact');
    expect(find.text(l10n.beaconFactsComposerTitle), findsNothing);
    expect(roomCubit.refreshes, 1);
    expect(
      roomCubit.state.factCards.map((f) => f.factText),
      [_factText],
    );

    // The room's own fact list (Attach › Fact) now offers the new fact.
    await _openFactPicker(tester, l10n);
    expect(
      find.descendant(
        of: find.byType(FactPickerSheet),
        matching: find.text(_factText),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.beaconRoomFactPickerPinFirst), findsNothing);
  });
  testWidgets('a cancelled Add-fact form does not re-read the fact cards', (
    tester,
  ) async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    final server = _ServerFactCards();
    final roomCubit = await _pumpRoom(tester, server);

    await _openAddFactForm(tester, l10n);
    final material = MaterialLocalizations.of(
      tester.element(find.text(l10n.beaconFactsComposerTitle)),
    );
    await tester.tap(find.text(material.cancelButtonLabel).last);
    await tester.pumpAndSettle();

    expect(find.text(l10n.beaconFactsComposerTitle), findsNothing);
    expect(server.pins, isEmpty);
    expect(roomCubit.refreshes, 0, reason: 'nothing was saved');
  });
}
