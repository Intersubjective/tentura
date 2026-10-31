// #862: saving the current line disables the field while it still holds focus
// on web unless enabled stays true until blur.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/platform/web_safe_text_field_enabled.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_current_line_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_threads/room_cubit_fakes.dart';

class _SlowNowLineRepo extends FakeBeaconThreadsRepository {
  _SlowNowLineRepo(this.completer) : super(userId: 'user-1');

  final Completer<BeaconRoomState> completer;

  @override
  Future<BeaconRoomState> updateRoomNowLine({
    required String beaconId,
    required String text,
    required int baseRevision,
  }) => completer.future;
}

void main() {
  late Completer<BeaconRoomState> saveDone;

  setUp(() async {
    debugWebTextInputConfigHold = true;
    saveDone = Completer<BeaconRoomState>();
    if (GetIt.I.isRegistered<BeaconThreadsCase>()) {
      await GetIt.I.unregister<BeaconThreadsCase>();
    }
    GetIt.I.registerSingleton<BeaconThreadsCase>(
      roomCubitMakeCase(_SlowNowLineRepo(saveDone)),
    );
  });

  tearDown(() async {
    debugWebTextInputConfigHold = false;
    if (GetIt.I.isRegistered<BeaconThreadsCase>()) {
      await GetIt.I.unregister<BeaconThreadsCase>();
    }
  });

  testWidgets('current line field stays enabled while focused during save', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBeaconCurrentLineSheet(
              context,
              beaconId: 'B1',
              initialText: 'Plan A',
              baseRevision: 1,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    await tester.enterText(field, 'Plan A');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(tester.widget<TextField>(field).enabled, isTrue);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);

    saveDone.complete(
      BeaconRoomState(
        beaconId: 'B1',
        updatedAt: DateTime.utc(2026),
        currentLine: 'Plan B',
        currentLineRevision: 2,
      ),
    );
    await tester.pump();
  });
}
