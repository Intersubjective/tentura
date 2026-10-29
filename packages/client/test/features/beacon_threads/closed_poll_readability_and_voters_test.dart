import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_poll_card.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'support/room_body_harness.dart';

const _viewer = Profile(id: 'viewer', displayName: 'Viewer');
const _alice = Profile(id: 'alice-voter', displayName: 'Alice');
const _dana = Profile(id: 'dana-non-voter', displayName: 'Dana');

RoomPollData _poll({
  bool anonymous = false,
  bool voted = false,
  PollType pollType = PollType.single,
}) => RoomPollData(
  id: 'day-poll',
  question: 'Which day works?',
  isAnonymous: anonymous,
  pollType: pollType,
  totalVotes: 1,
  myVariantIds: voted ? const ['sunday'] : const [],
  variants: const [
    RoomPollVariant(
      id: 'sunday',
      description: 'Sunday',
      votesCount: 1,
      avgScore: 4,
      voterIds: ['alice-voter'],
    ),
    RoomPollVariant(id: 'saturday', description: 'Saturday', votesCount: 0),
  ],
);

Future<void> _pumpPoll(
  WidgetTester tester, {
  required bool inRoom,
  bool closed = true,
  bool author = true,
  bool anonymous = false,
  bool voted = false,
  PollType pollType = PollType.single,
  Locale locale = const Locale('en'),
  Size size = const Size(1200, 900),
}) async {
  final poll = _poll(anonymous: anonymous, voted: voted, pollType: pollType);
  final participants = [
    roomBodyAdmittedParticipant(beaconId: 'b1', profile: _alice),
    roomBodyAdmittedParticipant(beaconId: 'b1', profile: _dana),
  ];
  if (inRoom) {
    await pumpBeaconRoomBody(
      tester,
      viewer: _viewer,
      width: size.width,
      height: size.height,
      locale: locale,
      roomState: roomBodyState(
        myUserId: _viewer.id,
        beaconStatus: closed ? BeaconStatus.closed : BeaconStatus.open,
        messages: [
          RoomMessage(
            id: 'poll-message',
            beaconId: 'b1',
            authorId: author ? _viewer.id : 'other-author',
            author: author
                ? _viewer
                : const Profile(id: 'other-author', displayName: 'Author'),
            body: poll.question,
            createdAt: DateTime.utc(2026),
            linkedPollingId: poll.id,
            pollDataJson: poll.encode(),
          ),
        ],
      ).copyWith(participants: participants, participantsLoaded: true),
    );
  } else {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      BlocProvider<ProfileCubit>.value(
        value: RoomBodyHarnessProfileCubit(_viewer),
        child: MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: locale,
          home: TenturaResponsiveScope(
            child: Scaffold(
              body: SingleChildScrollView(
                child: RoomPollCard(
                  poll: poll,
                  isClosed: closed,
                  isAuthor: author,
                  participants: participants,
                  onVote: (_, {score}) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  await tester.pumpAndSettle();
  expect(find.byType(RoomPollCard), findsOneWidget);
}

Color? _textColor(WidgetTester tester, String label) {
  final finder = find.descendant(
    of: find.byType(RoomPollCard),
    matching: find.text(label),
  );
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  return DefaultTextStyle.of(
    tester.element(finder),
  ).style.merge(text.style).color;
}

Decoration? _rowDecoration(WidgetTester tester, String label) {
  Container? rowContainer;
  tester.element(find.text(label)).visitAncestorElements((element) {
    if (element.widget case final Container container) {
      rowContainer = container;
      return false;
    }
    return true;
  });
  expect(rowContainer, isNotNull);
  return rowContainer!.decoration;
}

Color? _rowIconColor(WidgetTester tester, String label) {
  final row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  final icons = find.descendant(of: row, matching: find.byType(Icon));
  expect(icons, findsOneWidget);
  return tester.widget<Icon>(icons).color;
}

void main() {
  for (final inRoom in [false, true]) {
    group(inRoom ? 'Poll in a read-only room' : 'Closed poll card', () {
      for (final mobile in [false, true]) {
        testWidgets(
          'keeps readable result labels and option rows on '
          '${mobile ? 'a Russian phone' : 'an English desktop'}',
          (tester) async {
            final locale = Locale(mobile ? 'ru' : 'en');
            final size = mobile ? const Size(375, 667) : const Size(1200, 900);
            final labels = ['100%', '0%', '(1)', '(0)', 'Sunday', 'Saturday'];
            await _pumpPoll(
              tester,
              inRoom: inRoom,
              closed: false,
              locale: locale,
              size: size,
            );
            // An open author sees secondary result labels before voting.
            final openColors = {
              for (final label in labels) label: _textColor(tester, label),
            };
            await _pumpPoll(
              tester,
              inRoom: inRoom,
              locale: locale,
              size: size,
            );
            final closedColors = {
              for (final label in labels) label: _textColor(tester, label),
            };
            expect(
              closedColors,
              openColors,
              reason: 'Closing retains the colors of readable open results.',
            );
          },
        );
      }

      for (final pollType in PollType.values) {
        testWidgets(
          '${pollType.name} results retain selected and unselected row '
          'backgrounds and readable icons after closing',
          (tester) async {
            await _pumpPoll(
              tester,
              inRoom: inRoom,
              closed: false,
              voted: true,
              pollType: pollType,
            );
            // This baseline is genuinely open and voted, with voting enabled.
            expect(find.textContaining('Poll closed'), findsNothing);
            expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
            final openDecorations = {
              for (final label in ['Sunday', 'Saturday'])
                label: _rowDecoration(tester, label),
            };
            final openIcons = {
              for (final label in ['Sunday', 'Saturday'])
                label: _rowIconColor(tester, label),
            };
            final resultLabels = [
              if (pollType == PollType.range) ...[
                '4.0/5',
                '—',
              ] else ...[
                '100%',
                '0%',
              ],
              '(1)',
              '(0)',
              'Sunday',
              'Saturday',
            ];
            final openText = {
              for (final label in resultLabels)
                label: _textColor(tester, label),
            };
            await _pumpPoll(
              tester,
              inRoom: inRoom,
              voted: true,
              pollType: pollType,
            );
            expect({
              for (final label in resultLabels)
                label: _textColor(tester, label),
            }, openText);

            final cs = Theme.of(
              tester.element(find.byType(RoomPollCard)),
            ).colorScheme;
            final rowStyles = <String, Object?>{};
            for (final label in ['Sunday', 'Saturday']) {
              final row = find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(Row),
                  )
                  .first;
              final icons = find.descendant(
                of: row,
                matching: find.byType(Icon),
              );
              expect(icons, findsOneWidget);
              rowStyles['$label icon'] = tester.widget<Icon>(icons).color;
              rowStyles['$label decoration'] = _rowDecoration(tester, label);
            }
            expect(rowStyles, {
              'Sunday icon': openIcons['Sunday'],
              'Sunday decoration': openDecorations['Sunday'],
              'Saturday icon': openIcons['Saturday'],
              'Saturday decoration': openDecorations['Saturday'],
            });
            // Equality alone cannot detect shared faint styling in both states.
            expect(_rowIconColor(tester, 'Saturday'), cs.onSurfaceVariant);
          },
        );
      }

      for (final author in [true, false]) {
        testWidgets(
          '${author ? 'author' : 'helper without a vote'} can open named voters '
          'from the count only for non-anonymous polls',
          (tester) async {
            // Verify anonymous privacy first, then the positive interaction:
            // an absent voter list alone cannot satisfy this test.
            for (final anonymous in [true, false]) {
              // Remove the previous room/card so it cannot retain poll state.
              await tester.pumpWidget(const SizedBox.shrink());
              await _pumpPoll(
                tester,
                inRoom: inRoom,
                author: author,
                anonymous: anonymous,
              );
              final context = tester.element(find.byType(RoomPollCard));
              final l10n = L10n.of(context)!;
              final countLabel = l10n.beaconRoomPollVotesCount(1);
              final semantics = tester.ensureSemantics();
              try {
                final count = anonymous
                    ? find.text(l10n.beaconRoomPollClosedVotesCount(1))
                    : find.bySemanticsLabel(countLabel);
                expect(count, findsOneWidget);
                expect(
                  tester
                      .getSemantics(count)
                      .getSemanticsData()
                      .hasAction(SemanticsAction.tap),
                  !anonymous,
                  reason:
                      'The count itself is an actionable link only when public.',
                );
                expect(find.text('Alice'), findsNothing);
                expect(find.text('Dana'), findsNothing);
                await tester.ensureVisible(count);
                await tester.tap(count);
                await tester.pumpAndSettle();
                final voters = find.text('Alice');
                expect(voters, anonymous ? findsNothing : findsOneWidget);
                expect(find.text('Dana'), findsNothing);
              } finally {
                semantics.dispose();
              }
            }
          },
        );
      }
    });
  }
}
