import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/features/beacon_threads/domain/exception/now_line_changed_exception.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// #692: the "Update plan…" sheet (beacon app-bar overflow) kept Save enabled
// on a blank field, and the server then refused with "Plan text is
// required". It now greys out Save on blank text, like the other next-step
// editor.

/// Only what `showBeaconRoomUpdatePlanSheet` reads: the opened line and
/// `updatePlan`.
class _RoomCubitStub extends Fake implements RoomCubit {
  _RoomCubitStub(this.currentLine);

  final String currentLine;

  final plans = <String>[];

  @override
  RoomState get state => RoomState(
    beaconId: 'beacon-1',
    roomState: BeaconRoomState(
      beaconId: 'beacon-1',
      currentLine: currentLine,
      currentLineRevision: 1,
      updatedAt: DateTime.utc(2026),
    ),
  );

  @override
  Future<NowLineChangedException?> updatePlan(
    String currentLine, {
    required int baseRevision,
  }) async {
    plans.add(currentLine);
    return null;
  }
}

Future<void> _openUpdatePlanSheet(
  WidgetTester tester,
  _RoomCubitStub cubit,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBeaconRoomUpdatePlanSheet(
              context,
              cubit,
              L10n.of(context)!,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

FilledButton _saveButton(WidgetTester tester) => tester.widget<FilledButton>(
  find.widgetWithText(FilledButton, 'Save'),
);

void main() {
  group('Update plan sheet (#692)', () {
    testWidgets('clearing the line disables Save', (tester) async {
      final cubit = _RoomCubitStub('Van at 10:00');
      await _openUpdatePlanSheet(tester, cubit);

      expect(_saveButton(tester).onPressed, isNotNull);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(_saveButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      expect(_saveButton(tester).onPressed, isNull, reason: 'blank is empty');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(cubit.plans, isEmpty);
    });

    testWidgets('a blank line on open keeps Save disabled', (tester) async {
      final cubit = _RoomCubitStub('');
      await _openUpdatePlanSheet(tester, cubit);

      expect(_saveButton(tester).onPressed, isNull);
    });

    testWidgets('a non-blank line still saves', (tester) async {
      final cubit = _RoomCubitStub('');
      await _openUpdatePlanSheet(tester, cubit);

      await tester.enterText(find.byType(TextField), '  Buy pizza  ');
      await tester.pumpAndSettle();
      expect(_saveButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(cubit.plans, ['Buy pizza']);
      expect(find.byType(TextField), findsNothing, reason: 'sheet closed');
    });
  });
}
