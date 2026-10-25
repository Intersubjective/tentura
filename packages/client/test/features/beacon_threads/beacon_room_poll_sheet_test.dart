// The room's poll sheet keeps the draft when the server refuses the poll
// (including the duplicate-options code 1346, shown localized), and each option
// row keeps its own text when an option above it is removed.
//
// #737: the sheet had no Cancel or close button; the only exit was Escape.
// #728: «Send poll» was enabled on an empty form and answered with the
// app-wide error bar «Too short question».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_plan/data/model/beacon_plan_error_mapper.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
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

class _MockRoomCubit extends Mock implements RoomCubit {
  _MockRoomCubit({required this.result});

  final bool result;
  int createPollCalls = 0;

  @override
  Future<bool> createPoll({
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) async {
    createPollCalls++;
    return result;
  }
}

Future<void> _openSheet(
  WidgetTester tester,
  RoomCubit cubit, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBeaconRoomPollSheet(context, cubit: cubit),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _field(int index) => find.byType(TextFormField).at(index);

void main() {
  group('server refusal (1346)', () {
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
      testWidgets('a server duplicate refusal keeps the draft ($language)', (
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
        // Options the client sees as different: the server's own 1346 refusal
        // must still keep the draft and show the localized message.
        await tester.enterText(fields.at(1), 'Option A');
        await tester.enterText(fields.at(2), 'Option B');
        // Send is enabled once the form has a question and two options
        // (#728); let that rebuild land before tapping it.
        await tester.pump();
        final send = find.widgetWithText(
          FilledButton,
          l10n.beaconRoomSendPollButton,
        );
        await tester.ensureVisible(send);
        await tester.tap(send);
        await tester.pumpAndSettle();

        expect(repository.submittedVariants, ['Option A', 'Option B']);
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
  });

  testWidgets("removing an option keeps the other rows' text", (
    tester,
  ) async {
    await _openSheet(tester, _MockRoomCubit(result: true));
    final l10n = await L10n.delegate.load(const Locale('en'));

    await tester.tap(find.text(l10n.addOptionButton));
    await tester.pumpAndSettle();
    // Field 0 is the question; 1..3 are the options.
    await tester.enterText(_field(1), 'Alpha');
    await tester.enterText(_field(2), 'Bravo');
    await tester.enterText(_field(3), 'Charlie');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsNothing);
    expect(find.text('Bravo'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    expect(find.text('Poll options must be distinct'), findsNothing);
  });

  testWidgets('a refused poll keeps the sheet and its draft open', (
    tester,
  ) async {
    final cubit = _MockRoomCubit(result: false);
    await _openSheet(tester, cubit);
    final l10n = await L10n.delegate.load(const Locale('en'));

    await tester.enterText(_field(0), 'When do we meet?');
    await tester.enterText(_field(1), 'Monday');
    await tester.enterText(_field(2), 'Tuesday');
    await tester.pumpAndSettle();

    final send = find.text(l10n.beaconRoomSendPollButton);
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(cubit.createPollCalls, 1);
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Tuesday'), findsOneWidget);
    expect(find.text(l10n.beaconRoomSendPollButton), findsOneWidget);
  });

  testWidgets('options equal up to case and spaces are flagged', (
    tester,
  ) async {
    await _openSheet(tester, _MockRoomCubit(result: true));

    await tester.enterText(_field(1), 'Next Monday');
    await tester.enterText(_field(2), 'next  monday');
    await tester.pumpAndSettle();

    expect(find.text('Poll options must be distinct'), findsWidgets);
  });

  group('#737 #728 close and send', () {
    FilledButton sendButton(WidgetTester tester, L10n l10n) =>
        tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l10n.beaconRoomSendPollButton),
        );

    testWidgets('the close button closes an untouched sheet', (tester) async {
      await _openSheet(tester, _MockRoomCubit(result: true));
      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(find.text(l10n.beaconRoomCreatePoll), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.buttonClose));
      await tester.pumpAndSettle();

      expect(find.text(l10n.beaconRoomCreatePoll), findsNothing);
    });

    testWidgets('Cancel closes an untouched sheet', (tester) async {
      await _openSheet(tester, _MockRoomCubit(result: true));
      final l10n = await L10n.delegate.load(const Locale('en'));

      final cancel = find.widgetWithText(TextButton, l10n.buttonCancel);
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(find.text(l10n.beaconRoomCreatePoll), findsNothing);
    });

    testWidgets('closing a started poll asks before discarding it', (
      tester,
    ) async {
      await _openSheet(tester, _MockRoomCubit(result: true));
      final l10n = await L10n.delegate.load(const Locale('en'));
      await tester.enterText(_field(0), 'When do we meet?');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.buttonClose));
      await tester.pumpAndSettle();

      expect(find.text(l10n.composerDiscardTitle), findsOneWidget);
      await tester.tap(find.text(l10n.composerDiscardKeepEditing));
      await tester.pumpAndSettle();
      expect(find.text('When do we meet?'), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.buttonClose));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.composerDiscardConfirm));
      await tester.pumpAndSettle();
      expect(find.text(l10n.beaconRoomCreatePoll), findsNothing);
    });

    testWidgets('Send poll waits for a question and two options', (
      tester,
    ) async {
      final cubit = _MockRoomCubit(result: true);
      await _openSheet(tester, cubit);
      final l10n = await L10n.delegate.load(const Locale('en'));
      expect(sendButton(tester, l10n).onPressed, isNull);

      await tester.enterText(_field(1), 'Monday');
      await tester.enterText(_field(2), 'Tuesday');
      await tester.pumpAndSettle();
      expect(sendButton(tester, l10n).onPressed, isNull, reason: 'no question');

      await tester.enterText(_field(0), 'When do we meet?');
      await tester.enterText(_field(2), '  ');
      await tester.pumpAndSettle();
      expect(sendButton(tester, l10n).onPressed, isNull, reason: 'one option');

      await tester.enterText(_field(2), 'Tuesday');
      await tester.pumpAndSettle();
      expect(sendButton(tester, l10n).onPressed, isNotNull);
      expect(cubit.createPollCalls, 0);
    });

    // #784 review: the disabled Send poll gave no reason until a field was
    // touched; a helper line says what is missing.
    testWidgets('an empty form says what Send poll needs', (tester) async {
      await _openSheet(tester, _MockRoomCubit(result: true));
      expect(find.text('Add a question and two options'), findsOneWidget);

      await tester.enterText(_field(0), 'When do we meet?');
      await tester.enterText(_field(1), 'Monday');
      await tester.pumpAndSettle();
      expect(find.text('Add a question and two options'), findsOneWidget);

      await tester.enterText(_field(2), 'Tuesday');
      await tester.pumpAndSettle();
      expect(find.text('Add a question and two options'), findsNothing);
    });

    testWidgets('ru: an empty form says what Send poll needs', (tester) async {
      await _openSheet(
        tester,
        _MockRoomCubit(result: true),
        locale: const Locale('ru'),
      );
      expect(
        find.text('Добавьте вопрос и два варианта ответа'),
        findsOneWidget,
      );
    });

    testWidgets('a too short question is marked on the field, not in a '
        'snack bar', (tester) async {
      final cubit = _MockRoomCubit(result: true);
      await _openSheet(tester, cubit);
      final l10n = await L10n.delegate.load(const Locale('en'));

      await tester.enterText(_field(0), 'When?');
      await tester.enterText(_field(1), 'Monday');
      await tester.enterText(_field(2), 'Tuesday');
      await tester.pumpAndSettle();
      final send = find.widgetWithText(
        FilledButton,
        l10n.beaconRoomSendPollButton,
      );
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(cubit.createPollCalls, 0);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(TextFormField).first,
          matching: find.text('Too short question'),
        ),
        findsOneWidget,
      );
    });
  });
}
