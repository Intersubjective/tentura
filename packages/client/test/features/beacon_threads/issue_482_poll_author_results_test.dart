import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_poll_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// Issue #482: the poll author must see counts and percentages without
// voting, still be able to vote, and the "N votes" footer must read as
// regular secondary text (not the disabled-looking outline grey).

const _sun = 'variant-sun';
const _sat = 'variant-sat';

RoomPollData _poll({PollType pollType = PollType.single}) => RoomPollData(
  id: 'poll-482',
  question: 'Which day works?',
  pollType: pollType,
  isAnonymous: false,
  myVariantIds: const [],
  totalVotes: 3,
  variants: [
    RoomPollVariant(
      id: _sun,
      description: 'Sunday',
      votesCount: 2,
      avgScore: pollType == PollType.range ? 4 : null,
    ),
    RoomPollVariant(
      id: _sat,
      description: 'Saturday',
      votesCount: 1,
      avgScore: pollType == PollType.range ? 2 : null,
    ),
  ],
);

Widget _app(Widget child) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('author who has not voted sees per-option percentages and '
      'counts', (tester) async {
    await tester.pumpWidget(
      _app(
        RoomPollCard(
          poll: _poll(),
          isAuthor: true,
          onVote: (_, {score}) {},
        ),
      ),
    );

    expect(find.text('67%'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('(2)'), findsOneWidget);
    expect(find.text('(1)'), findsOneWidget);
    expect(find.text('3 votes'), findsOneWidget);
  });

  testWidgets('author who has not voted can still cast a vote', (
    tester,
  ) async {
    final votes = <List<String>>[];
    await tester.pumpWidget(
      _app(
        RoomPollCard(
          poll: _poll(),
          isAuthor: true,
          onVote: (variantIds, {score}) => votes.add(variantIds),
        ),
      ),
    );

    await tester.tap(find.text('Saturday'));
    await tester.pump();

    expect(votes, [
      [_sat],
    ]);
  });

  testWidgets('author of a multiple-choice poll sees percentages and can '
      'still submit', (tester) async {
    await tester.pumpWidget(
      _app(
        RoomPollCard(
          poll: _poll(pollType: PollType.multiple),
          isAuthor: true,
          onVote: (_, {score}) {},
        ),
      ),
    );

    expect(find.text('67%'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Submit'), findsOneWidget);
  });

  testWidgets('author of a range poll sees average scores without voting', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RoomPollCard(
          poll: _poll(pollType: PollType.range),
          isAuthor: true,
          onVote: (_, {score}) {},
        ),
      ),
    );

    expect(find.text('4.0/5'), findsOneWidget);
    expect(find.text('2.0/5'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Submit ratings'),
      findsOneWidget,
    );
  });

  testWidgets('a non-author who has not voted still sees no results', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(RoomPollCard(poll: _poll(), onVote: (_, {score}) {})),
    );

    expect(find.textContaining('%'), findsNothing);
    expect(find.text('(2)'), findsNothing);
    expect(find.text('(1)'), findsNothing);
    // The total stays visible, as before.
    expect(find.text('3 votes'), findsOneWidget);
  });

  testWidgets('the votes footer uses regular secondary text, not the '
      'disabled-looking outline colour', (tester) async {
    await tester.pumpWidget(
      _app(RoomPollCard(poll: _poll(), onVote: (_, {score}) {})),
    );

    final cs = TenturaTheme.light().colorScheme;
    expect(cs.onSurfaceVariant, isNot(cs.outline));
    final footer = tester.widget<Text>(find.text('3 votes'));
    expect(footer.style?.color, cs.onSurfaceVariant);
  });
}
