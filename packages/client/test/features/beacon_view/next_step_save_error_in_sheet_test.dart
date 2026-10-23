import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_current_line_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_threads/room_cubit_fakes.dart';

// #603: a next-step save that failed for a reason other than a conflict
// showed its error in a snackbar on the screen behind the open sheet, where
// nobody could see it; the sheet just stopped spinning.

class _FailingNowLineRepo extends FakeBeaconThreadsRepository {
  _FailingNowLineRepo() : super(userId: 'user-1');

  Object? error = StateError('database busy');
  final writes = <String>[];

  @override
  Future<BeaconRoomState> updateRoomNowLine({
    required String beaconId,
    required String text,
    required int baseRevision,
  }) async {
    final e = error;
    if (e != null) throw e;
    writes.add(text);
    return BeaconRoomState(
      beaconId: beaconId,
      currentLine: text,
      currentLineRevision: baseRevision + 1,
      updatedAt: DateTime.utc(2026),
    );
  }
}

const _errorText = 'Bad state: database busy';

Future<void> _openSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBeaconCurrentLineSheet(
              context,
              beaconId: 'beacon-1',
              initialText: 'Ship the beta',
              baseRevision: 1,
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

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  late _FailingNowLineRepo repo;

  setUp(() {
    repo = _FailingNowLineRepo();
    if (GetIt.I.isRegistered<BeaconThreadsCase>()) {
      GetIt.I.unregister<BeaconThreadsCase>();
    }
    GetIt.I.registerSingleton<BeaconThreadsCase>(roomCubitMakeCase(repo));
  });

  tearDown(() async {
    if (GetIt.I.isRegistered<BeaconThreadsCase>()) {
      await GetIt.I.unregister<BeaconThreadsCase>();
    }
  });

  testWidgets('a failed save shows its error inside the open sheet', (
    tester,
  ) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), 'Van at 9:45');
    await tester.pumpAndSettle();

    await _save(tester);

    // The sheet stays open with the text, and the error is in it, where the
    // person can see it (not behind the sheet).
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Van at 9:45'), findsOneWidget);
    expect(
      find
          .descendant(
            of: find.byType(TextField),
            matching: find.text(_errorText),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(repo.writes, isEmpty);
  });

  testWidgets('editing clears the error and a retry saves and closes', (
    tester,
  ) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), 'Van at 9:45');
    await tester.pumpAndSettle();
    await _save(tester);
    expect(find.text(_errorText), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Van at 10:00');
    await tester.pumpAndSettle();
    expect(find.text(_errorText), findsNothing);

    repo.error = null;
    await _save(tester);

    expect(repo.writes, ['Van at 10:00']);
    expect(find.byType(TextField), findsNothing);
  });

  // Guard: a save that goes through closes the sheet with no error.
  testWidgets('a successful save closes the sheet', (tester) async {
    repo.error = null;
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), 'Van at 9:45');
    await tester.pumpAndSettle();

    await _save(tester);

    expect(repo.writes, ['Van at 9:45']);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(_errorText), findsNothing);
  });
}
