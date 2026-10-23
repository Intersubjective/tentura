import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_poll_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

// Issue #609 (from #482): once the Request is final (read-only), every
// viewer sees a poll's results (bars, %, counts, averages), whether they
// voted or not, with no vote controls and a "Poll closed" header. Open
// polls behave as before.

const _sun = 'variant-sun';
const _sat = 'variant-sat';

RoomPollData _poll({
  PollType pollType = PollType.single,
  List<String> myVariantIds = const [],
}) => RoomPollData(
  id: 'poll-609',
  question: 'Which day works?',
  pollType: pollType,
  isAnonymous: false,
  myVariantIds: myVariantIds,
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

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: locale,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('closed single-choice poll shows results to a viewer who '
      'never voted, with no way to vote', (tester) async {
    final votes = <List<String>>[];
    await tester.pumpWidget(
      _app(
        RoomPollCard(
          poll: _poll(),
          isClosed: true,
          onVote: (variantIds, {score}) => votes.add(variantIds),
        ),
      ),
    );

    expect(find.text('67%'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.text('(2)'), findsOneWidget);
    expect(find.text('(1)'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    expect(find.text('Poll closed · 3 votes'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    expect(find.text('Change answer'), findsNothing);

    await tester.tap(find.text('Saturday'));
    await tester.pump();
    expect(votes, isEmpty);
  });

  testWidgets('closed multiple-choice poll shows results and no Submit', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RoomPollCard(
          poll: _poll(pollType: PollType.multiple),
          isClosed: true,
          onVote: (_, {score}) {},
        ),
      ),
    );

    expect(find.text('67%'), findsOneWidget);
    expect(find.text('33%'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
  });

  testWidgets('closed range poll shows averages and no rating controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RoomPollCard(
          poll: _poll(pollType: PollType.range),
          isClosed: true,
          onVote: (_, {score}) {},
        ),
      ),
    );

    expect(find.text('4.0/5'), findsOneWidget);
    expect(find.text('2.0/5'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('closed poll hides Change answer from a voter', (tester) async {
    await tester.pumpWidget(
      _app(
        RoomPollCard(
          poll: _poll(myVariantIds: const [_sun]),
          isClosed: true,
          onVote: (_, {score}) {},
        ),
      ),
    );

    expect(find.text('67%'), findsOneWidget);
    expect(find.text('Change answer'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('Poll closed · 3 votes'), findsOneWidget);
  });

  testWidgets('closed poll header is localized in Russian', (tester) async {
    await tester.pumpWidget(
      _app(
        RoomPollCard(poll: _poll(), isClosed: true),
        locale: const Locale('ru'),
      ),
    );

    expect(find.text('Опрос закрыт · 3 голоса'), findsOneWidget);
  });

  testWidgets('open poll for a viewer who has not voted is unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(RoomPollCard(poll: _poll(), onVote: (_, {score}) {})),
    );

    expect(find.textContaining('%'), findsNothing);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
    expect(find.text('3 votes'), findsOneWidget);
    expect(find.textContaining('Poll closed'), findsNothing);
  });
}
