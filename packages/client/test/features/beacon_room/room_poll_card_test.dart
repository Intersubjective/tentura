import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_poll_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  testWidgets('range poll uses score chips and submits selected rating', (
    tester,
  ) async {
    final votes = <({List<String> variantIds, int? score})>[];
    const poll = RoomPollData(
      id: 'poll-1',
      question: 'How useful is this?',
      pollType: PollType.range,
      isAnonymous: true,
      allowRevote: true,
      myVariantIds: [],
      totalVotes: 0,
      variants: [
        RoomPollVariant(
          id: 'variant-a',
          description: 'Range item A',
          votesCount: 0,
        ),
        RoomPollVariant(
          id: 'variant-b',
          description: 'Range item B',
          votesCount: 0,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: RoomPollCard(
            poll: poll,
            onVote: (variantIds, {score}) =>
                votes.add((variantIds: variantIds, score: score)),
          ),
        ),
      ),
    );

    expect(find.byType(Slider), findsNothing);
    expect(find.byType(ChoiceChip), findsNWidgets(10));

    await tester.tap(find.widgetWithText(ChoiceChip, '4').first);
    await tester.pump();
    await tester.tap(find.text('Submit ratings'));
    await tester.pump();

    expect(votes, hasLength(1));
    expect(votes.single.variantIds, ['variant-a']);
    expect(votes.single.score, 4);
  });
}
