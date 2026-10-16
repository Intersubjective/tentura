import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_plan/data/model/beacon_plan_error_mapper.dart';
import 'package:tentura/features/beacon_threads/ui/widget/beacon_room_poll_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

class _DuplicatePollRepository extends FakeBeaconThreadsRepository {
  _DuplicatePollRepository() : super(userId: kRoomCubitFakeMyUserId);

  List<String>? submittedVariants;

  @override
  Future<void> createPoll({
    required String beaconId,
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) async {
    submittedVariants = variants;
    throwIfBeaconPlanError(1346, const {'code': '1346'});
  }
}

void main() {
  setUp(() {
    GetIt.I.registerSingleton<Logger>(Logger('poll-sheet-test'));
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  for (final (language, message) in const [
    ('en', 'Poll options must be distinct'),
    ('ru', 'Варианты ответа в опросе должны различаться'),
  ]) {
    testWidgets('duplicate options stay editable with $language message', (
      tester,
    ) async {
      final repository = _DuplicatePollRepository();
      final effects = FakeUiEffectPort();
      final cubit = roomCubitForTest(repository, effects: effects);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      late L10n l10n;
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          locale: Locale(language),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                l10n = L10n.of(context)!;
                return TextButton(
                  onPressed: () =>
                      showBeaconRoomPollSheet(context, cubit: cubit),
                  child: const Text('Open poll'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open poll'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Choose an option');
      await tester.enterText(fields.at(1), 'Same option');
      await tester.enterText(fields.at(2), 'Same option');
      final send = find.widgetWithText(
        FilledButton,
        l10n.beaconRoomSendPollButton,
      );
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(repository.submittedVariants, ['Same option', 'Same option']);
      expect(effects.emitted, isEmpty);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(message, findRichText: true),
        ),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(tester.widget<FilledButton>(send).onPressed, isNotNull);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
