import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_poll_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// Issue #609 (from #482): the poll buttons "Submit", "Submit ratings" and
// "Change answer" were hard-coded English; they must follow the app locale.

RoomPollData _poll({
  required PollType pollType,
  List<String> myVariantIds = const [],
}) => RoomPollData(
  id: 'poll-609',
  question: 'Which day works?',
  pollType: pollType,
  isAnonymous: true,
  allowRevote: true,
  myVariantIds: myVariantIds,
  totalVotes: myVariantIds.length,
  variants: const [
    RoomPollVariant(id: 'variant-sun', description: 'Sunday', votesCount: 0),
    RoomPollVariant(id: 'variant-sat', description: 'Saturday', votesCount: 0),
  ],
);

Widget _app(Locale locale, RoomPollData poll) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: locale,
  home: Scaffold(
    body: SingleChildScrollView(
      child: RoomPollCard(poll: poll, onVote: (_, {score}) {}),
    ),
  ),
);

void main() {
  testWidgets('range poll submit button is localized in Russian', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const Locale('ru'), _poll(pollType: PollType.range)),
    );

    expect(
      find.widgetWithText(FilledButton, 'Отправить оценки'),
      findsOneWidget,
    );
    expect(find.text('Submit ratings'), findsNothing);
  });

  testWidgets('multiple-choice submit button is localized in Russian', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const Locale('ru'), _poll(pollType: PollType.multiple)),
    );

    expect(find.widgetWithText(FilledButton, 'Отправить'), findsOneWidget);
    expect(find.text('Submit'), findsNothing);
  });

  testWidgets('change answer button is localized in Russian', (tester) async {
    await tester.pumpWidget(
      _app(
        const Locale('ru'),
        _poll(pollType: PollType.single, myVariantIds: ['variant-sun']),
      ),
    );

    expect(find.widgetWithText(TextButton, 'Изменить ответ'), findsOneWidget);
    expect(find.text('Change answer'), findsNothing);
  });

  testWidgets('English labels are unchanged', (tester) async {
    await tester.pumpWidget(
      _app(const Locale('en'), _poll(pollType: PollType.range)),
    );
    expect(
      find.widgetWithText(FilledButton, 'Submit ratings'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _app(
        const Locale('en'),
        _poll(pollType: PollType.single, myVariantIds: ['variant-sun']),
      ),
    );
    expect(find.widgetWithText(TextButton, 'Change answer'), findsOneWidget);
  });
}
