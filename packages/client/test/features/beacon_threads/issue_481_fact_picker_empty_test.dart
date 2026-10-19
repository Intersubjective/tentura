// #481: the empty quote picker was a dead end. With no facts it must offer
// "Pin your first fact", which closes the picker and hands off to the
// host's Add-fact form (`onAddFact`).
//
// Fails to compile until `showFactPickerSheet` / `FactPickerSheet` take an
// optional `VoidCallback? onAddFact` and the l10n key
// `beaconRoomFactPickerPinFirst` exists (en + ru).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/fact_picker_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'support/room_body_harness.dart';

BeaconFactCard _fact(String id) => BeaconFactCard(
  id: id,
  beaconId: 'b1',
  factText: 'Door code 4711',
  visibility: BeaconFactCardVisibilityBits.public,
  pinnedBy: 'peer-1',
  pinnedByTitle: 'Peer',
  createdAt: DateTime.utc(2026),
  status: BeaconFactCardStatusBits.active,
);

Future<void> _pumpPicker(
  WidgetTester tester, {
  required RoomCubit cubit,
  VoidCallback? onAddFact,
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: TenturaResponsiveScope(
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showFactPickerSheet(
                ctx,
                cubit: cubit,
                onAddFact: onAddFact,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('#481 empty fact picker', () {
    testWidgets(
      'offers Pin your first fact, which closes the picker and opens '
      'the Add-fact form',
      (tester) async {
        final l10n = await L10n.delegate.load(const Locale('en'));
        final cubit = RoomBodyHarnessCubit(roomBodyState());
        var addFactCalls = 0;

        await _pumpPicker(
          tester,
          cubit: cubit,
          onAddFact: () => addFactCalls++,
        );

        final pinFirst = find.descendant(
          of: find.byType(FactPickerSheet),
          matching: find.text(l10n.beaconRoomFactPickerPinFirst),
        );
        expect(
          pinFirst,
          findsOneWidget,
          reason: 'an empty picker must offer a way to pin the first fact',
        );
        expect(addFactCalls, 0);

        await tester.tap(pinFirst);
        await tester.pumpAndSettle();

        expect(
          find.byType(FactPickerSheet),
          findsNothing,
          reason: 'the picker closes before the Add-fact form opens',
        );
        expect(
          addFactCalls,
          1,
          reason: 'Pin your first fact must hand off to the Add-fact form',
        );
      },
    );

    testWidgets('a picker with facts does not offer Pin your first fact', (
      tester,
    ) async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final cubit = RoomBodyHarnessCubit(
        roomBodyState().copyWith(factCards: [_fact('f1')]),
      );

      await _pumpPicker(tester, cubit: cubit, onAddFact: () {});

      expect(find.textContaining('Door code 4711'), findsOneWidget);
      expect(find.text(l10n.beaconRoomFactPickerPinFirst), findsNothing);
    });

    testWidgets(
      'without an Add-fact handler the empty picker shows no dead button',
      (tester) async {
        final l10n = await L10n.delegate.load(const Locale('en'));
        final cubit = RoomBodyHarnessCubit(roomBodyState());

        await _pumpPicker(tester, cubit: cubit);

        expect(find.text(l10n.beaconFactsSheetEmpty), findsOneWidget);
        expect(find.text(l10n.beaconRoomFactPickerPinFirst), findsNothing);
      },
    );

    test('Pin your first fact is translated (en + ru)', () async {
      final en = await L10n.delegate.load(const Locale('en'));
      final ru = await L10n.delegate.load(const Locale('ru'));
      expect(en.beaconRoomFactPickerPinFirst.trim(), isNotEmpty);
      expect(ru.beaconRoomFactPickerPinFirst.trim(), isNotEmpty);
      expect(
        ru.beaconRoomFactPickerPinFirst,
        isNot(en.beaconRoomFactPickerPinFirst),
        reason: 'ru must carry a real translation, not the English copy',
      );
    });
  });
}
