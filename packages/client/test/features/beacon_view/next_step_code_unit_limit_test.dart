import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_current_line_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_threads/room_cubit_fakes.dart';

// #343: the next-step editors capped the line with TextField.maxLength,
// which counts user-perceived characters, while the server
// (BeaconRoomCase: `trimmed.length > kBeaconRoomCurrentLineMaxLength`)
// counts UTF-16 code units. An emoji counts once in the field and twice on
// the server, so a line the counter showed as 60/60 was refused on Save.

/// The issue text: 70 characters, 71 UTF-16 code units (the van is two).
const _typed =
    'Confirm the van 🚐 and the time with Vadim, then buy pizza for everyone';

/// Its longest prefix the server takes: 59 characters, 60 code units.
const _fits = 'Confirm the van 🚐 and the time with Vadim, then buy pizza f';

/// What a character-counting cap keeps: 60 characters, 61 code units.
const _charCapped =
    'Confirm the van 🚐 and the time with Vadim, then buy pizza fo';

/// The cap lands inside the emoji: 60 characters, 61 code units. A cut at 60
/// code units would leave a lone high surrogate; the right cut drops the
/// whole emoji.
final _cutsEmoji = '${'a' * 59}🚐';

/// What the server-sized cap keeps of [_cutsEmoji]: 59 code units.
final _cutsEmojiKept = 'a' * 59;

class _RecordingRepo extends FakeBeaconThreadsRepository {
  _RecordingRepo() : super(userId: 'user-1');

  final writes = <String>[];

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async =>
      BeaconRoomState(beaconId: beaconId, updatedAt: DateTime.utc(2026));

  @override
  Future<BeaconRoomState> updateRoomNowLine({
    required String beaconId,
    required String text,
  }) async {
    writes.add(text);
    return BeaconRoomState(
      beaconId: beaconId,
      currentLine: text,
      updatedAt: DateTime.utc(2026),
    );
  }
}

/// Only what `showBeaconRoomUpdatePlanSheet` reads: the opened line and
/// `updatePlan`.
class _RoomCubitStub extends Fake implements RoomCubit {
  final plans = <String>[];

  @override
  RoomState get state => const RoomState(beaconId: 'beacon-1');

  @override
  Future<void> updatePlan(
    String currentLine, {
    required String? expectedLine,
  }) async => plans.add(currentLine);
}

Widget _app(Widget Function(BuildContext context) button) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  theme: TenturaTheme.light(),
  home: Scaffold(body: Builder(builder: button)),
);

Future<void> _openNextStepSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    _app(
      (context) => TextButton(
        onPressed: () => showBeaconCurrentLineSheet(
          context,
          beaconId: 'beacon-1',
          initialText: '',
        ),
        child: const Text('open'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _openUpdatePlanSheet(
  WidgetTester tester,
  _RoomCubitStub cubit,
) async {
  await tester.pumpWidget(
    _app(
      (context) => TextButton(
        onPressed: () =>
            showBeaconRoomUpdatePlanSheet(context, cubit, L10n.of(context)!),
        child: const Text('open'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// True when [s] holds a UTF-16 surrogate that is not half of a pair.
bool _hasLoneSurrogate(String s) {
  for (var i = 0; i < s.length; i++) {
    final u = s.codeUnitAt(i);
    if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 >= s.length) return true;
      final next = s.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i++;
    } else if (u >= 0xDC00 && u <= 0xDFFF) {
      return true;
    }
  }
  return false;
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  test('fixture strings measure as the comments say', () {
    expect(kBeaconRoomCurrentLineMaxLength, 60);
    expect(_typed.length, 71);
    expect(_fits.length, 60);
    expect(_fits.characters.length, 59);
    expect(_charCapped.length, 61);
    expect(_charCapped.characters.length, 60);
    expect(_cutsEmoji.length, 61);
    expect(_cutsEmoji.characters.length, 60);
  });

  group('next-step sheet (Now tab pencil)', () {
    late _RecordingRepo repo;

    setUp(() async {
      repo = _RecordingRepo();
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

    testWidgets('a line with an emoji is capped at 60 code units', (
      tester,
    ) async {
      await _openNextStepSheet(tester);

      await tester.enterText(find.byType(TextField), _typed);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), _fits);
      expect(find.text('60/60'), findsOneWidget);
      expect(find.text('59/60'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.writes, [_fits]);
      expect(repo.writes.single.length, lessThanOrEqualTo(60));
      expect(find.byType(TextField), findsNothing, reason: 'sheet closed');
    });

    testWidgets('the counter counts code units, and a 60/60 line saves', (
      tester,
    ) async {
      await _openNextStepSheet(tester);

      await tester.enterText(find.byType(TextField), _fits);
      await tester.pumpAndSettle();

      // Untouched: it already fits, emoji and all.
      expect(_fieldText(tester), _fits);
      expect(find.text('60/60'), findsOneWidget);
      expect(find.text('59/60'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.writes, [_fits]);
    });

    testWidgets('a cap inside an emoji drops the whole emoji', (
      tester,
    ) async {
      await _openNextStepSheet(tester);

      await tester.enterText(find.byType(TextField), _cutsEmoji);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), _cutsEmojiKept);
      expect(find.text('59/60'), findsOneWidget);
      expect(find.text('60/60'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(repo.writes, [_cutsEmojiKept]);
      expect(_hasLoneSurrogate(repo.writes.single), isFalse);
    });
  });

  group('Update plan sheet', () {
    testWidgets('a line with an emoji is capped at 60 code units', (
      tester,
    ) async {
      final cubit = _RoomCubitStub();
      await _openUpdatePlanSheet(tester, cubit);

      await tester.enterText(find.byType(TextField), _typed);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), _fits);
      expect(find.text('60/60'), findsOneWidget);
      expect(find.text('59/60'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(cubit.plans, [_fits]);
    });

    testWidgets('a cap inside an emoji drops the whole emoji', (
      tester,
    ) async {
      final cubit = _RoomCubitStub();
      await _openUpdatePlanSheet(tester, cubit);

      await tester.enterText(find.byType(TextField), _cutsEmoji);
      await tester.pumpAndSettle();

      expect(_fieldText(tester), _cutsEmojiKept);
      expect(find.text('59/60'), findsOneWidget);
      expect(find.text('60/60'), findsNothing);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(cubit.plans, [_cutsEmojiKept]);
      expect(_hasLoneSurrogate(cubit.plans.single), isFalse);
    });
  });
}
