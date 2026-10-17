import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/features/beacon_threads/domain/exception/now_line_changed_exception.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_current_line_sheet.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_threads/room_cubit_fakes.dart';

// B085 (QA round 2): two people edit the next step at once; the second
// save silently replaced the first, and nobody was told.

class _NowLineRepo extends FakeBeaconThreadsRepository {
  _NowLineRepo({required this.serverLine}) : super(userId: 'user-1');

  String serverLine;
  bool failRead = false;
  final writes = <String>[];

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async {
    if (failRead) throw StateError('database busy');
    return BeaconRoomState(
      beaconId: beaconId,
      currentLine: serverLine,
      updatedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<BeaconRoomState> updateRoomNowLine({
    required String beaconId,
    required String text,
  }) async {
    writes.add(text);
    serverLine = text;
    return BeaconRoomState(
      beaconId: beaconId,
      currentLine: text,
      updatedAt: DateTime.utc(2026),
    );
  }
}

Future<void> _pumpSheet(WidgetTester tester, String initialText) async {
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
              initialText: initialText,
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

void main() {
  group('BeaconThreadsCase.updateRoomNowLine with expectedLine', () {
    test(
      'writes when the server still has the line the editor opened',
      () async {
        final repo = _NowLineRepo(serverLine: 'Van at 9:45');
        final sut = roomCubitMakeCase(repo);

        await sut.updateRoomNowLine(
          beaconId: 'beacon-1',
          currentLine: 'Van at 10:00',
          expectedLine: 'Van at 9:45',
        );

        expect(repo.writes, ['Van at 10:00']);
      },
    );

    test(
      'refuses to overwrite a line someone else changed meanwhile',
      () async {
        final repo = _NowLineRepo(serverLine: 'AUTHOR version');
        final sut = roomCubitMakeCase(repo);

        await expectLater(
          sut.updateRoomNowLine(
            beaconId: 'beacon-1',
            currentLine: 'NINA version',
            expectedLine: 'Van at 9:45',
          ),
          throwsA(
            isA<NowLineChangedException>().having(
              (e) => e.currentLine,
              'currentLine',
              'AUTHOR version',
            ),
          ),
        );
        expect(repo.writes, isEmpty);
      },
    );

    // Fails on the base: a failed pre-read failed the whole save.
    test('a failed pre-read still saves (as before the check)', () async {
      final repo = _NowLineRepo(serverLine: 'Van at 9:45')..failRead = true;
      final sut = roomCubitMakeCase(repo);

      await sut.updateRoomNowLine(
        beaconId: 'beacon-1',
        currentLine: 'NINA version',
        expectedLine: 'Van at 9:45',
      );

      expect(repo.writes, ['NINA version']);
    });

    test('no expectedLine keeps the old blind write', () async {
      final repo = _NowLineRepo(serverLine: 'AUTHOR version');
      final sut = roomCubitMakeCase(repo);

      await sut.updateRoomNowLine(
        beaconId: 'beacon-1',
        currentLine: 'NINA version',
      );

      expect(repo.writes, ['NINA version']);
    });
  });

  // Fails on the base: RoomCubit.updatePlan (the "Update plan" sheet and
  // "use message as plan") wrote without expectedLine, so it overwrote blind.
  group('RoomCubit.updatePlan', () {
    setUp(() => registerRoomCubitProfileCubit('user-1'));

    test('refuses a stale save', () async {
      final repo = _NowLineRepo(serverLine: 'AUTHOR version');
      final cubit = roomCubitForTest(repo);
      addTearDown(cubit.close);

      await cubit.updatePlan('NINA version', expectedLine: 'Van at 9:45');

      expect(repo.writes, isEmpty);
    });

    // Fails before the #531 follow-up: the sheet is already closed on this
    // path, yet the snackbar said "Save again", which there is no way to do.
    test(
      'a stale save says to reopen Update plan, not to save again',
      () async {
        final repo = _NowLineRepo(serverLine: 'AUTHOR version');
        final effects = FakeUiEffectPort();
        final cubit = roomCubitForTest(repo, effects: effects);
        addTearDown(cubit.close);

        await cubit.updatePlan('NINA version', expectedLine: 'Van at 9:45');

        final shown = effects.emitted
            .whereType<ShowError>()
            .map((e) => e.error)
            .whereType<Localizable>()
            .single;
        expect(shown.toEn, contains('AUTHOR version'));
        expect(shown.toEn, contains('Update plan'));
        expect(shown.toEn, isNot(contains('Save again')));
        expect(shown.toRu, contains('Обновить план'));
      },
    );

    test('saves when the line is unchanged', () async {
      final repo = _NowLineRepo(serverLine: 'Van at 9:45');
      final cubit = roomCubitForTest(repo);
      addTearDown(cubit.close);

      await cubit.updatePlan('NINA version', expectedLine: 'Van at 9:45');

      expect(repo.writes, ['NINA version']);
    });
  });

  group('next-step sheet', () {
    late _NowLineRepo repo;

    setUp(() async {
      repo = _NowLineRepo(serverLine: 'Van at 9:45');
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

    testWidgets('a concurrent change is shown, and a second Save replaces it', (
      tester,
    ) async {
      await _pumpSheet(tester, 'Van at 9:45');
      // Someone else saves while this editor is open.
      repo.serverLine = 'AUTHOR version';

      await tester.enterText(find.byType(TextField), 'NINA version');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.writes, isEmpty);
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: 'sheet stays open',
      );
      expect(find.textContaining('AUTHOR version'), findsWidgets);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.writes, ['NINA version']);
      expect(find.byType(TextField), findsNothing);
    });

    // Fails on the base: the conflict note stayed under the field while the
    // person edited.
    testWidgets('editing again clears the conflict note', (tester) async {
      await _pumpSheet(tester, 'Van at 9:45');
      repo.serverLine = 'AUTHOR version';
      await tester.enterText(find.byType(TextField), 'NINA version');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Someone changed'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'NINA version 2');
      // The error text fades out with the decorator's animation.
      await tester.pumpAndSettle();

      expect(find.textContaining('Someone changed'), findsNothing);
    });
  });
}
