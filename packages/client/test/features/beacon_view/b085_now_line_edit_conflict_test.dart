import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/features/beacon_threads/data/model/now_line_error_mapper.dart';
import 'package:tentura/features/beacon_threads/domain/exception/now_line_changed_exception.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_current_line_sheet.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';

// B085 (QA round 2), #517: two people edit the next step at once; the second
// save silently replaced the first, and nobody was told. The server now
// checks the revision the editor opened with; this fake does the same.

class _NowLineRepo extends FakeBeaconThreadsRepository {
  _NowLineRepo({required this.serverLine, this.serverRevision = 1})
    : super(userId: 'user-1');

  String serverLine;
  int serverRevision;
  final writes = <String>[];
  final bases = <int>[];

  /// Someone else saves while this person edits.
  void changeElsewhere(String line) {
    serverLine = line;
    serverRevision++;
  }

  BeaconRoomState _state(String beaconId) => BeaconRoomState(
    beaconId: beaconId,
    currentLine: serverLine,
    currentLineRevision: serverRevision,
    updatedAt: DateTime.utc(2026),
  );

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async =>
      _state(beaconId);

  @override
  Future<BeaconRoomState> updateRoomNowLine({
    required String beaconId,
    required String text,
    required int baseRevision,
  }) async {
    bases.add(baseRevision);
    if (baseRevision != serverRevision && text.trim() != serverLine) {
      throw NowLineChangedException(
        currentLine: serverLine,
        currentRevision: serverRevision,
      );
    }
    writes.add(text);
    if (text.trim() != serverLine) changeElsewhere(text.trim());
    return _state(beaconId);
  }
}

Widget _app(Widget Function(BuildContext context) button) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: Scaffold(body: Builder(builder: button)),
);

void main() {
  group('throwIfNowLineError', () {
    test('maps server code 1348 with the saved line and revision', () {
      expect(
        () => throwIfNowLineError(1348, {
          'code': '1348',
          'currentLine': 'AUTHOR version',
          'currentRevision': 7,
          'updatedBy': 'U-author',
        }),
        throwsA(
          isA<NowLineChangedException>()
              .having((e) => e.currentLine, 'currentLine', 'AUTHOR version')
              .having((e) => e.currentRevision, 'currentRevision', 7)
              .having((e) => e.updatedBy, 'updatedBy', 'U-author'),
        ),
      );
    });

    test('leaves other codes to the generic mapping', () {
      expect(() => throwIfNowLineError(1347, const {}), returnsNormally);
      expect(() => throwIfNowLineError(null, null), returnsNormally);
    });
  });

  group('BeaconThreadsCase.updateRoomNowLine', () {
    test('sends the base revision and returns the saved state', () async {
      final repo = _NowLineRepo(serverLine: 'Van at 9:45');
      final sut = roomCubitMakeCase(repo);

      final saved = await sut.updateRoomNowLine(
        beaconId: 'beacon-1',
        currentLine: 'Van at 10:00',
        baseRevision: 1,
      );

      expect(repo.bases, [1]);
      expect(repo.writes, ['Van at 10:00']);
      expect(saved.currentLine, 'Van at 10:00');
      expect(saved.currentLineRevision, 2);
    });

    test('a stale base is refused with the line saved now', () async {
      final repo = _NowLineRepo(serverLine: 'Van at 9:45')
        ..changeElsewhere('AUTHOR version');
      final sut = roomCubitMakeCase(repo);

      await expectLater(
        sut.updateRoomNowLine(
          beaconId: 'beacon-1',
          currentLine: 'NINA version',
          baseRevision: 1,
        ),
        throwsA(
          isA<NowLineChangedException>()
              .having((e) => e.currentLine, 'currentLine', 'AUTHOR version')
              .having((e) => e.currentRevision, 'currentRevision', 2),
        ),
      );
      expect(repo.writes, isEmpty);
    });
  });

  group('RoomCubit.updatePlan', () {
    setUp(() => registerRoomCubitProfileCubit('user-1'));

    test('a stale save writes nothing, returns the refusal and shows the '
        'newer line', () async {
      final repo = _NowLineRepo(serverLine: 'Van at 9:45');
      final effects = FakeUiEffectPort();
      final cubit = roomCubitForTest(repo, effects: effects);
      addTearDown(cubit.close);
      repo.changeElsewhere('AUTHOR version');

      final refused = await cubit.updatePlan('NINA version', baseRevision: 1);

      expect(repo.writes, isEmpty);
      expect(refused?.currentLine, 'AUTHOR version');
      expect(refused?.currentRevision, 2);
      expect(cubit.state.roomState?.currentLine, 'AUTHOR version');
      expect(cubit.state.roomState?.currentLineRevision, 2);
      expect(
        effects.emitted.whereType<ShowError>(),
        isEmpty,
        reason: 'the caller reopens its editor instead',
      );
    });

    test('a save on the current revision goes through', () async {
      final repo = _NowLineRepo(serverLine: 'Van at 9:45');
      final cubit = roomCubitForTest(repo);
      addTearDown(cubit.close);

      final refused = await cubit.updatePlan('NINA version', baseRevision: 1);

      expect(refused, isNull);
      expect(repo.writes, ['NINA version']);
    });
  });

  group('"Update plan" sheet', () {
    setUp(() => registerRoomCubitProfileCubit('user-1'));

    testWidgets('a concurrent change reopens the sheet with my text and '
        'theirs; saving again re-applies mine on the newer revision', (
      tester,
    ) async {
      final repo = _NowLineRepo(serverLine: 'Van at 9:45');
      late RoomCubit cubit;
      await tester.runAsync(() async {
        cubit = roomCubitForTest(repo);
        await cubit.load();
      });
      addTearDown(cubit.close);
      expect(cubit.state.roomState?.currentLineRevision, 1);

      await tester.pumpWidget(
        _app(
          (context) => TextButton(
            onPressed: () => showBeaconRoomUpdatePlanSheet(
              context,
              cubit,
              L10n.of(context)!,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      repo.changeElsewhere('AUTHOR version');
      await tester.enterText(find.byType(TextField), 'NINA version');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.writes, isEmpty);
      expect(find.byType(TextField), findsOneWidget, reason: 'reopened');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'NINA version',
      );
      expect(find.textContaining('AUTHOR version'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.bases, [1, 2]);
      expect(repo.writes, ['NINA version']);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('next-step sheet', () {
    late _NowLineRepo repo;
    late List<String> shownBehind;

    setUp(() async {
      repo = _NowLineRepo(serverLine: 'Van at 9:45');
      shownBehind = [];
      if (GetIt.I.isRegistered<BeaconThreadsCase>()) {
        await GetIt.I.unregister<BeaconThreadsCase>();
      }
      GetIt.I.registerSingleton<BeaconThreadsCase>(roomCubitMakeCase(repo));
    });

    tearDown(() async {
      if (GetIt.I.isRegistered<BeaconThreadsCase>()) {
        await GetIt.I.unregister<BeaconThreadsCase>();
      }
    });

    Future<void> pumpSheet(WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          (context) => TextButton(
            onPressed: () => showBeaconCurrentLineSheet(
              context,
              beaconId: 'beacon-1',
              initialText: 'Van at 9:45',
              baseRevision: 1,
              onSaved: (saved) => shownBehind.add(saved.currentLine),
              onStale: (newer) => shownBehind.add(newer.currentLine),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> saveStale(WidgetTester tester) async {
      repo.changeElsewhere('AUTHOR version');
      await tester.enterText(find.byType(TextField), 'NINA version');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('a concurrent change is shown, and a second Save replaces it', (
      tester,
    ) async {
      await pumpSheet(tester);
      await saveStale(tester);

      expect(repo.writes, isEmpty);
      expect(find.byType(TextField), findsOneWidget, reason: 'stays open');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'NINA version',
        reason: 'their text is kept',
      );
      expect(find.textContaining('AUTHOR version'), findsOneWidget);
      expect(
        shownBehind,
        ['AUTHOR version'],
        reason: 'the screen behind shows the newer line at once',
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.bases, [1, 2]);
      expect(repo.writes, ['NINA version']);
      expect(shownBehind, ['AUTHOR version', 'NINA version']);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('"Keep their version" closes without saving', (tester) async {
      await pumpSheet(tester);
      expect(find.text('Keep their version'), findsNothing);
      await saveStale(tester);

      await tester.tap(find.text('Keep their version'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(repo.writes, isEmpty);
      expect(shownBehind, ['AUTHOR version']);
    });

    testWidgets('editing again clears the conflict note', (tester) async {
      await pumpSheet(tester);
      await saveStale(tester);
      expect(find.textContaining('Someone changed'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'NINA version 2');
      // The error text fades out with the decorator's animation.
      await tester.pumpAndSettle();

      expect(find.textContaining('Someone changed'), findsNothing);
    });
  });
}
